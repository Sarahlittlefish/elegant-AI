import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 他用哪个模型回话。默认是魔搭（ModelScope）上免费的 GLM-5.2，
/// DeepSeek-V4.1-Flash 是同一个魔搭令牌的备用，智谱 glm-4.6 是原来那个收费的。
/// 三个都是 OpenAI 那种标准接口，请求格式一样，只有地址、模型名、关思考的写法不一样。
enum Provider: String, Codable, CaseIterable {
    case modelscope
    case zhipu

    var endpoint: URL {
        switch self {
        case .modelscope: return URL(string: "https://api-inference.modelscope.cn/v1/chat/completions")!
        case .zhipu: return URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
        }
    }

    /// 设置页里显示的名字
    var keyName: String {
        switch self {
        case .modelscope: return "魔搭令牌"
        case .zhipu: return "智谱 API Key"
        }
    }
}

enum ModelOption: String, Codable, CaseIterable, Identifiable {
    case glm52 = "ZhipuAI/GLM-5.2"
    case deepseekFlash = "deepseek-ai/DeepSeek-V4.1-Flash-1017"
    case glm46 = "glm-4.6"

    static let defaultOption: ModelOption = .glm52

    var id: String { rawValue }
    var modelName: String { rawValue }

    var provider: Provider {
        switch self {
        case .glm52, .deepseekFlash: return .modelscope
        case .glm46: return .zhipu
        }
    }

    var displayName: String {
        switch self {
        case .glm52: return "GLM-5.2（魔搭，免费，推荐）"
        case .deepseekFlash: return "DeepSeek-V4.1-Flash（魔搭，免费，备用）"
        case .glm46: return "glm-4.6（智谱，收费，原来那个）"
        }
    }

    var shortName: String {
        switch self {
        case .glm52: return "GLM-5.2"
        case .deepseekFlash: return "DeepSeek-V4.1-Flash"
        case .glm46: return "glm-4.6"
        }
    }

    /// 主模型不行时自动换的那个：两个魔搭模型互为备用（同一个令牌）。智谱的不自动换。
    var fallback: ModelOption? {
        switch self {
        case .glm52: return .deepseekFlash
        case .deepseekFlash: return .glm52
        case .glm46: return nil
        }
    }
}

enum ModelConfig {
    static let temperature = 0.9
    /// 发给模型的聊天记录上限（开场记录总是全部带上）。网页版不设上限，这里留个很宽的保险。
    static let maxRecentMessages = 600
    /// 429、服务器出错、网络断了：等这么多秒再试一次。
    static let retryDelaySeconds: UInt64 = 3
}

struct ChatTurn: Equatable {
    let role: String
    var content: String
}

enum ModelError: LocalizedError {
    case noKey(Provider)
    case http(Int, String, Provider)
    case badResponse

    /// 值得原样再试一次的：额度/太忙（429）、服务器出错（5xx）。
    var isRetryable: Bool {
        if case .http(let code, _, _) = self { return code == 429 || code >= 500 }
        return false
    }

    /// 模型被下架或改名：魔搭会回 400「Invalid model id」。
    var isModelUnavailable: Bool {
        if case .http(let code, let body, _) = self {
            return (code == 400 || code == 404) && body.lowercased().contains("model")
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .noKey(let provider):
            return "还没填\(provider.keyName)（右上角齿轮里填）"
        case .http(let code, let body, let provider):
            switch code {
            case 401, 403:
                return "\(provider.keyName)不对或过期了，去右上角齿轮里重新填（\(code)）"
            case 429:
                return provider == .modelscope
                    ? "魔搭今天的免费次数用完了，或者现在太忙。过一会再发，或者在设置里换成 glm-4.6（429）"
                    : "智谱现在太忙或额度不够，过一会再发（429）"
            default:
                if isModelUnavailable {
                    return "这个模型现在用不了（可能下架了），去设置里换一个（\(code)）"
                }
                return "模型接口出错 \(code): \(body.prefix(160))"
            }
        case .badResponse:
            return "模型返回的内容看不懂"
        }
    }
}

/// 往 OpenAI 那种标准接口发一次聊天请求。网页版 api/chat/route.ts 的做法一样：
/// 温度 0.9，关闭思考模式；system = 人设 + 档案（+ 当前时间），后面是全部聊天记录。
struct ModelClient {
    var option: ModelOption
    var apiKey: String
    var temperature: Double = ModelConfig.temperature
    var session: URLSession = .shared

    /// 把聊天记录变成 user / assistant 交替的轮次：去掉「没发出去」的提示，
    /// 同一方连着的几条（比如开头两条剪贴板、他连发的两句）用空行合成一条。
    static func turns(from messages: [ChatMessage]) -> [ChatTurn] {
        var turns: [ChatTurn] = []
        for message in messages where !message.isError {
            let role = message.sender == .user ? "user" : "assistant"
            if let last = turns.last, last.role == role {
                turns[turns.count - 1].content += "\n\n" + message.content
            } else {
                turns.append(ChatTurn(role: role, content: message.content))
            }
        }
        return turns
    }

    /// 开场记录全部保留，之后的只取最近 maxRecentMessages 条。
    static func trimmed(_ messages: [ChatMessage]) -> [ChatMessage] {
        let seed = messages.filter { $0.isSeed }
        let rest = messages.filter { !$0.isSeed }
        return seed + rest.suffix(ModelConfig.maxRecentMessages)
    }

    /// 智谱 glm-4.5 及以后的模型默认会先"思考"，聊天不需要，关掉更快也更像真人。
    static func needsThinkingDisabled(_ model: String) -> Bool {
        model.range(of: #"^glm-(4\.[5-9]|[5-9])"#, options: .regularExpression) != nil
    }

    /// 关思考模式：魔搭用 enable_thinking: false，智谱用 thinking: {type: disabled}。
    static func thinkingOff(for option: ModelOption) -> [String: Any] {
        switch option.provider {
        case .modelscope:
            return ["enable_thinking": false]
        case .zhipu:
            return needsThinkingDisabled(option.modelName) ? ["thinking": ["type": "disabled"]] : [:]
        }
    }

    func makeRequest(systemPrompt: String, messages: [ChatMessage]) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ModelError.noKey(option.provider) }

        var payloadMessages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for turn in Self.turns(from: Self.trimmed(messages)) {
            payloadMessages.append(["role": turn.role, "content": turn.content])
        }
        var body: [String: Any] = [
            "model": option.modelName,
            "messages": payloadMessages,
            "temperature": temperature,
        ]
        body.merge(Self.thinkingOff(for: option)) { _, new in new }

        var request = URLRequest(url: option.provider.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 发一次请求，拿回他的整段回复（还没拆气泡）。
    func reply(systemPrompt: String, messages: [ChatMessage]) async throws -> String {
        let request = try makeRequest(systemPrompt: systemPrompt, messages: messages)
        let (data, response) = try await Self.send(request, with: session)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ModelError.http(status, String(data: data, encoding: .utf8) ?? "", option.provider)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else { throw ModelError.badResponse }
        return Self.cleanReply(message["content"] as? String ?? "")
    }

    /// 出错时要不要原样再试一次：429、5xx、网络超时/断网。
    static func shouldRetry(_ error: Error) -> Bool {
        if let modelError = error as? ModelError { return modelError.isRetryable }
        return error is URLError
    }

    /// 出错时要不要换备用模型：能重试的那些，加上模型下架。令牌不对（401）换了也没用。
    static func shouldFallBack(_ error: Error) -> Bool {
        if let modelError = error as? ModelError { return modelError.isRetryable || modelError.isModelUnavailable }
        return error is URLError
    }

    /// 主模型先发；遇到 429 / 服务器出错 / 网络问题，等几秒再试一次；
    /// 还不行（或者模型下架了），魔搭的就换另一个魔搭模型试一次。
    /// 返回回复和真正回话的那个模型。
    static func replyWithFallback(primary: ModelOption,
                                  keys: [Provider: String],
                                  systemPrompt: String,
                                  messages: [ChatMessage],
                                  session: URLSession = .shared,
                                  retryDelaySeconds: UInt64 = ModelConfig.retryDelaySeconds) async throws -> (String, ModelOption) {
        let first = ModelClient(option: primary, apiKey: keys[primary.provider] ?? "", session: session)
        var lastError: Error
        do {
            return (try await first.reply(systemPrompt: systemPrompt, messages: messages), primary)
        } catch {
            lastError = error
        }
        if shouldRetry(lastError) {
            try? await Task.sleep(nanoseconds: retryDelaySeconds * 1_000_000_000)
            do {
                return (try await first.reply(systemPrompt: systemPrompt, messages: messages), primary)
            } catch {
                lastError = error
            }
        }
        if let backup = primary.fallback, shouldFallBack(lastError) {
            let second = ModelClient(option: backup, apiKey: keys[backup.provider] ?? "", session: session)
            do {
                return (try await second.reply(systemPrompt: systemPrompt, messages: messages), backup)
            } catch {
                // 备用也不行：报主模型的那个错，更好懂。
            }
        }
        throw lastError
    }

    /// 万一模型把思考过程写进回复里，去掉；空回复显示成「...」。
    static func cleanReply(_ raw: String) -> String {
        var text = raw
        if let range = text.range(of: "</think>", options: .backwards) {
            text = String(text[range.upperBound...])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "..." : text
    }

    /// 他用空行隔开的几句话，拆成连发的几个气泡（和网页版一样）。
    static func splitBubbles(_ reply: String) -> [String] {
        let parts = reply
            .replacingOccurrences(of: #"\n\s*\n"#, with: "\u{0}", options: .regularExpression)
            .components(separatedBy: "\u{0}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? ["..."] : parts
    }

    /// 用回调包一层，iPad 和我这边的 Linux 检查环境都能用。
    private static func send(_ request: URLRequest, with session: URLSession) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: ModelError.badResponse)
                }
            }
            task.resume()
        }
    }
}
