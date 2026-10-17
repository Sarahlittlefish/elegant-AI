// 在 Linux 上检查 app 的核心逻辑（不含界面）：人设拼接、开场记录、拆气泡、主动消息时间、真实调一次智谱。
// 用法见 ios/tools/linux-check/run.sh
import Foundation

final class MemoryKeyStore: KeyStoring {
    var key: String
    init(_ key: String) { self.key = key }
    func loadKey() -> String { key }
    func saveKey(_ key: String) { self.key = key }
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

check(ZhipuClient.splitBubbles("Fascinating...\n\nMay—be(?") == ["Fascinating...", "May—be(?"], "空行拆成两个气泡")
check(ZhipuClient.splitBubbles("a\n \n\n b\nc") == ["a", "b\nc"], "多个空行也只拆一次，单换行不拆")
check(ZhipuClient.cleanReply("<think>x</think>\n hi ") == "hi", "去掉思考过程")
check(ZhipuClient.needsThinkingDisabled("glm-4.6") && !ZhipuClient.needsThinkingDisabled("glm-4"), "glm-4.6 会关闭思考模式")

let msgs = SeedHistory.messages(from: seed) + [ChatMessage(sender: .kai, content: "err", isError: true)]
let turns = ZhipuClient.turns(from: msgs)
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
let key = ProcessInfo.processInfo.environment["ZHIPU_API_KEY"] ?? ""
let store = await ChatStore(history: HistoryFile(url: tmp), seed: seed, keyStore: MemoryKeyStore(key),
                            systemPrompt: .success(prompt))
await MainActor.run {
    check(store.receivePing(at: Date()), "主动「?」能记进聊天记录")
    check(!store.receivePing(at: Date().addingTimeInterval(5)), "没回的「?」不会连着加第二个")
}
await store.send("（测试 iPad app）你那边现在几点")
let after = await MainActor.run { store.messages }
let replies = after.suffix(from: seed.count + 2)
for r in replies { print("他：\(r.content)\(r.isError ? "  [出错]" : "")") }
check(!replies.isEmpty && !replies.contains { $0.isError }, "真实调用智谱成功")
let reloaded = HistoryFile(url: tmp).load() ?? []
check(reloaded.count == after.count, "聊天记录存进文件、重新读出来一样多（\(reloaded.count) 条）")
