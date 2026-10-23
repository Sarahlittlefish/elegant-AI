// 在 Linux 上检查 app 的核心逻辑（不含界面）：人设拼接、开场记录、拆气泡、主动消息时间、真实调一次魔搭模型、模拟出错时的重试和换备用、升级不丢记录。
// 用法见 ios/tools/linux-check/run.sh
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MemoryKeyStore: KeyStoring {
    var keys: [Provider: String]
    init(_ keys: [Provider: String]) { self.keys = keys }
    func loadKey(for provider: Provider) -> String { keys[provider] ?? "" }
    func saveKey(_ key: String, for provider: Provider) { keys[provider] = key }
}

func check(_ ok: Bool, _ what: String) {
    print(ok ? "通过  \(what)" : "失败  \(what)")
    if !ok { exit(1) }
}

let repo = URL(fileURLWithPath: CommandLine.arguments[1])
let persona = try String(contentsOf: repo.appendingPathComponent("kai_persona_v2.md"), encoding: .utf8)
let profile = try String(contentsOf: repo.appendingPathComponent("kai_profile.md"), encoding: .utf8)
let prompt = Persona.systemPrompt(persona: persona, profile: profile)
let expected = try String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), encoding: .utf8)
check(prompt == expected, "系统提示词和网页版 loadKaiPersona() 一字不差（\(prompt.count) 字）")

let seedData = try Data(contentsOf: repo.appendingPathComponent("ios/Kai/Resources/seed_history.json"))
let seed = try SeedHistory.decode(seedData)
check(seed.count > 0 && seed.first?.sender == .user, "开场记录读得出来（\(seed.count) 条）")

check(ModelClient.splitBubbles("Fascinating...\n\nMay—be(?") == ["Fascinating...", "May—be(?"], "空行拆成两个气泡")
check(ModelClient.splitBubbles("a\n \n\n b\nc") == ["a", "b\nc"], "多个空行也只拆一次，单换行不拆")
check(ModelClient.cleanReply("<think>x</think>\n hi ") == "hi", "去掉思考过程")
check(ModelClient.needsThinkingDisabled("glm-4.6") && !ModelClient.needsThinkingDisabled("glm-4"), "glm-4.6 会关闭思考模式")
check(ModelClient.thinkingOff(for: .glm52)["enable_thinking"] as? Bool == false
      && ModelClient.thinkingOff(for: .deepseekFlash)["enable_thinking"] as? Bool == false, "魔搭模型用 enable_thinking: false 关思考")
check(ModelClient.thinkingOff(for: .glm46)["thinking"] != nil && ModelClient.thinkingOff(for: .glm46)["enable_thinking"] == nil, "智谱 glm-4.6 还是用 thinking: disabled")
check(ModelOption.defaultOption == .glm52 && ModelOption.glm52.fallback == .deepseekFlash && ModelOption.glm46.fallback == nil, "默认 GLM-5.2，备用 DeepSeek，glm-4.6 不自动换")
let e429 = ModelError.http(429, "rate", .modelscope), e401 = ModelError.http(401, "auth", .modelscope)
let eGone = ModelError.http(400, "{\"error\":{\"message\":\"Invalid model id: ZhipuAI/GLM-5.2\"}}", .modelscope)
check(ModelClient.shouldRetry(e429) && ModelClient.shouldFallBack(e429), "429 先重试，再换备用")
check(!ModelClient.shouldRetry(e401) && !ModelClient.shouldFallBack(e401), "令牌不对（401）不重试也不换")
check(!ModelClient.shouldRetry(eGone) && ModelClient.shouldFallBack(eGone), "模型下架（400 Invalid model id）直接换备用")
check(ModelClient.shouldRetry(URLError(.timedOut)), "网络超时会重试")
print("出错提示示例：" + (e429.errorDescription ?? ""))
print("出错提示示例：" + (e401.errorDescription ?? ""))
print("出错提示示例：" + (eGone.errorDescription ?? ""))
let req = try ModelClient(option: .glm52, apiKey: "ms-test").makeRequest(systemPrompt: "s", messages: [ChatMessage(sender: .user, content: "hi")])
let reqBody = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
check(req.url?.absoluteString == "https://api-inference.modelscope.cn/v1/chat/completions"
      && reqBody["model"] as? String == "ZhipuAI/GLM-5.2" && reqBody["temperature"] as? Double == 0.9
      && reqBody["enable_thinking"] as? Bool == false && reqBody["thinking"] == nil, "GLM-5.2 请求：魔搭地址、模型名、温度 0.9、关思考")

let msgs = SeedHistory.messages(from: seed) + [ChatMessage(sender: .kai, content: "err", isError: true)]
let turns = ModelClient.turns(from: msgs)
check(!turns.contains { $0.content.contains("err") }, "出错提示不发给模型")
check(zip(turns, turns.dropFirst()).allSatisfy { $0.role != $1.role }, "user / assistant 严格交替")

var rng = SystemRandomNumberGenerator()
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeContext.beijing
let now = Date()
for _ in 0..<500 {
    let d = PingPlanner().nextPingDate(after: now, using: &rng)
    let h = cal.component(.hour, from: d)
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day!
    if !(19..<22).contains(h) || !(1...3).contains(days) { check(false, "主动消息时间 \(d)") }
}
check(true, "主动消息时间都在 1–3 天后的北京时间 19:00–22:00")
print("示例时间行：" + TimeContext.line(now: now))

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kai_check_\(UUID().uuidString)/chat_history.json")
// 不连网，模拟魔搭出错，检查「重试一次 → 换备用」真的会走。
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var calls: [String] = []
    nonisolated(unsafe) static var failing: [String: Int] = [:]   // 模型名 → 返回的错误码
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); var data = Data(); var buf = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close(); body = data
        }
        let json = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any]
        let model = json?["model"] as? String ?? "?"
        Self.calls.append(model)
        let code = Self.failing[model] ?? 200
        let payload = code == 200
            ? #"{"choices":[{"message":{"role":"assistant","content":"stub reply"}}]}"#
            : (code == 400 ? #"{"error":{"message":"Invalid model id: \#(model)"}}"# : #"{"error":{"message":"rate limited"}}"#)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let stubConfig = URLSessionConfiguration.ephemeral
stubConfig.protocolClasses = [StubProtocol.self]
let stubSession = URLSession(configuration: stubConfig)
let stubKeys: [Provider: String] = [.modelscope: "ms-test", .zhipu: "z-test"]
let oneMsg = [ChatMessage(sender: .user, content: "hi")]

StubProtocol.failing = ["ZhipuAI/GLM-5.2": 429]; StubProtocol.calls = []
let (r1, used1) = try await ModelClient.replyWithFallback(primary: .glm52, keys: stubKeys, systemPrompt: "s", messages: oneMsg,
                                                          session: stubSession, retryDelaySeconds: 0)
check(r1 == "stub reply" && used1 == .deepseekFlash && StubProtocol.calls == ["ZhipuAI/GLM-5.2", "ZhipuAI/GLM-5.2", "deepseek-ai/DeepSeek-V4.1-Flash-1017"],
      "GLM-5.2 一直 429：重试一次，再自动换 DeepSeek 回（\(StubProtocol.calls.count) 次请求）")

StubProtocol.failing = ["ZhipuAI/GLM-5.2": 400]; StubProtocol.calls = []
let (_, used2) = try await ModelClient.replyWithFallback(primary: .glm52, keys: stubKeys, systemPrompt: "s", messages: oneMsg,
                                                         session: stubSession, retryDelaySeconds: 0)
check(used2 == .deepseekFlash && StubProtocol.calls.count == 2, "GLM-5.2 下架（400）：不重试，直接换 DeepSeek")

StubProtocol.failing = ["ZhipuAI/GLM-5.2": 401, "deepseek-ai/DeepSeek-V4.1-Flash-1017": 401]; StubProtocol.calls = []
do {
    _ = try await ModelClient.replyWithFallback(primary: .glm52, keys: stubKeys, systemPrompt: "s", messages: oneMsg,
                                                session: stubSession, retryDelaySeconds: 0)
    check(false, "401 应该报错")
} catch {
    check(StubProtocol.calls.count == 1 && (error as? ModelError)?.errorDescription?.contains("令牌") == true, "令牌不对（401）：只发一次，提示重新填令牌")
}

StubProtocol.failing = ["ZhipuAI/GLM-5.2": 429, "deepseek-ai/DeepSeek-V4.1-Flash-1017": 429]; StubProtocol.calls = []
do {
    _ = try await ModelClient.replyWithFallback(primary: .glm52, keys: stubKeys, systemPrompt: "s", messages: oneMsg,
                                                session: stubSession, retryDelaySeconds: 0)
    check(false, "两个都 429 应该报错")
} catch {
    check(StubProtocol.calls.count == 3 && (error as? ModelError)?.isRetryable == true, "两个都 429：一共 3 次请求，然后显示中文提示")
}

StubProtocol.failing = ["glm-4.6": 429]; StubProtocol.calls = []
do {
    _ = try await ModelClient.replyWithFallback(primary: .glm46, keys: stubKeys, systemPrompt: "s", messages: oneMsg,
                                                session: stubSession, retryDelaySeconds: 0)
    check(false, "glm-4.6 429 应该报错")
} catch {
    check(StubProtocol.calls == ["glm-4.6", "glm-4.6"], "glm-4.6 出错：只重试一次，不会自动换到魔搭")
}

let env = ProcessInfo.processInfo.environment
let keyStore = MemoryKeyStore([.zhipu: env["ZHIPU_API_KEY"] ?? "", .modelscope: env["MODELSCOPE_API_KEY"] ?? ""])
let suite = "kai_check_\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
// 模拟老版本升级：老聊天记录文件已经在了，只有智谱 Key，没有魔搭令牌。
let oldHistory = SeedHistory.messages(from: seed) + [ChatMessage(sender: .user, content: "（老记录）升级前的一句", date: Date()),
                                                    ChatMessage(sender: .kai, content: "（老记录）他的回复", date: Date())]
HistoryFile(url: tmp).save(oldHistory)
let upgraded = await ChatStore(history: HistoryFile(url: tmp), seed: seed, keyStore: MemoryKeyStore([.zhipu: "old-zhipu-key"]),
                               systemPrompt: .success(prompt), defaults: defaults)
await MainActor.run {
    check(upgraded.messages.count == oldHistory.count && upgraded.messages.last?.content == "（老记录）他的回复", "升级后老聊天记录一条不少（\(upgraded.messages.count) 条）")
    check(upgraded.selectedModel == .glm52 && !upgraded.hasKey, "升级后默认 GLM-5.2，没填魔搭令牌时会弹出填令牌")
    check(upgraded.hasKey(for: .zhipu), "原来的智谱 Key 还在")
    upgraded.selectModel(.glm46)
    check(upgraded.hasKey, "换成 glm-4.6 就能直接用原来的智谱 Key")
}
let reopened = await ChatStore(history: HistoryFile(url: tmp), seed: seed, keyStore: MemoryKeyStore([:]),
                               systemPrompt: .success(prompt), defaults: defaults)
check(await MainActor.run { reopened.selectedModel } == .glm46, "选的模型存下来了，重开还是 glm-4.6")
defaults.removePersistentDomain(forName: suite)
HistoryFile(url: tmp).save(SeedHistory.messages(from: seed))

let store = await ChatStore(history: HistoryFile(url: tmp), seed: seed, keyStore: keyStore,
                            systemPrompt: .success(prompt), defaults: UserDefaults(suiteName: suite + "b")!)
await MainActor.run {
    check(store.receivePing(at: Date()), "主动「?」能记进聊天记录")
    check(!store.receivePing(at: Date().addingTimeInterval(5)), "没回的「?」不会连着加第二个")
}
let models: [ModelOption] = (env["CHECK_MODELS"] ?? "glm52,deepseekFlash").split(separator: ",").compactMap { name in
    ModelOption.allCases.first { "\($0)" == name }
}
for model in models {
    await MainActor.run { store.selectModel(model) }
    let before = await MainActor.run { store.messages.count }
    let started = Date()
    await store.send("（测试 iPad app）你那边现在几点")
    let after = await MainActor.run { store.messages }
    let used = await MainActor.run { store.lastReplyModel }
    let replies = after.suffix(from: before + 1)
    for r in replies { print("他（\(model.shortName)，实际 \(used?.shortName ?? "-")，\(String(format: "%.1f", Date().timeIntervalSince(started)))s）：\(r.content)\(r.isError ? "  [出错]" : "")") }
    check(!replies.isEmpty && !replies.contains { $0.isError }, "真实调用 \(model.shortName) 成功")
}
let reloaded = HistoryFile(url: tmp).load() ?? []
let finalCount = await MainActor.run { store.messages.count }
check(reloaded.count == finalCount, "聊天记录存进文件、重新读出来一样多（\(reloaded.count) 条）")
