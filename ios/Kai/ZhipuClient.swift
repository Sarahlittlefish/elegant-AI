import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 直接从 iPad 调智谱接口，和网页版 api/chat/route.ts 的做法一样：
/// glm-4.6，温度 0.9，关闭思考模式；system = 人设 + 档案（+ 当前时间），后面是全部聊天记录。
enum ZhipuConfig {
    static let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
    static let model = "glm-4.6"
    static let temperature = 0.9
    /// 发给模型的聊天记录上限（开场记录总是全部带上）。网页版不设上限，这里留个很宽的保险。
    static let maxRecentMessages = 600
}

struct ChatTurn: Equatable {
    let role: String
    var content: String
}

enum ZhipuError: LocalizedError {
    case noKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey: return "还没填智谱 API Key（右上角齿轮里填）"
        case .http(let code, let body): return "模型接口异常 \(code): \(body.prefix(200))"
        case .badResponse: return "模型返回的内容看不懂"
        }
    }
}

struct ZhipuClient {
    var apiKey: String
    var model: String = ZhipuConfig.model
    var temperature: Double = ZhipuConfig.temperature
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
        return seed + rest.suffix(ZhipuConfig.maxRecentMessages)
    }

    /// glm-4.5 及以后的模型默认会先"思考"，聊天不需要，关掉更快也更像真人。
    static func needsThinkingDisabled(_ model: String) -> Bool {
        model.range(of: #"^glm-(4\.[5-9]|[5-9])"#, options: .regularExpression) != nil
    }

    func makeRequest(systemPrompt: String, messages: [ChatMessage]) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ZhipuError.noKey }

        var payloadMessages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for turn in Self.turns(from: Self.trimmed(messages)) {
            payloadMessages.append(["role": turn.role, "content": turn.content])
        }
        var body: [String: Any] = [
            "model": model,
            "messages": payloadMessages,
            "temperature": temperature,
        ]
        if Self.needsThinkingDisabled(model) {
            body["thinking"] = ["type": "disabled"]
        }

        var request = URLRequest(url: ZhipuConfig.endpoint)
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
            throw ZhipuError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else { throw ZhipuError.badResponse }
        return Self.cleanReply(message["content"] as? String ?? "")
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
                    continuation.resume(throwing: ZhipuError.badResponse)
                }
            }
            task.resume()
        }
    }
}
