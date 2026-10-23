import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Combine)
import Combine
#endif

/// 存放魔搭令牌和智谱 Key 的地方，两个分开存。iPad 上用钥匙串（KeychainKeyStore），不写进代码、不上 GitHub。
protocol KeyStoring {
    func loadKey(for provider: Provider) -> String
    func saveKey(_ key: String, for provider: Provider)
}

/// 聊天记录存在 iPad 本地的一个 JSON 文件里，重开 app 还在。
struct HistoryFile {
    let url: URL

    func load() -> [ChatMessage]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([ChatMessage].self, from: data), !list.isEmpty else { return nil }
        return list
    }

    func save(_ messages: [ChatMessage]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(messages) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage]
    @Published private(set) var isLoading = false
    /// 现在选的模型要用的那个令牌 / Key 填了没有。
    @Published private(set) var hasKey: Bool
    /// 设置里选的模型，默认魔搭 GLM-5.2。存在 iPad 上，重装也还在。
    @Published private(set) var selectedModel: ModelOption
    /// 上一条回复真正是哪个模型回的（主模型不行时会自动换备用）。
    @Published private(set) var lastReplyModel: ModelOption?

    private let history: HistoryFile
    private let seed: [ChatMessage]
    private let keyStore: KeyStoring
    private let systemPromptBase: String?
    private let loadError: String?
    private let session: URLSession
    private let defaults: UserDefaults
    private static let selectedModelKey = "selected_model"

    init(history: HistoryFile,
         seed: [SeedMessage],
         keyStore: KeyStoring,
         systemPrompt: Result<String, Error>,
         session: URLSession = .shared,
         defaults: UserDefaults = .standard) {
        let seedMessages = SeedHistory.messages(from: seed)
        self.history = history
        self.seed = seedMessages
        self.keyStore = keyStore
        self.session = session
        self.defaults = defaults
        switch systemPrompt {
        case .success(let text):
            systemPromptBase = text
            loadError = nil
        case .failure(let error):
            systemPromptBase = nil
            loadError = error.localizedDescription
        }
        messages = history.load() ?? seedMessages
        let model = defaults.string(forKey: Self.selectedModelKey).flatMap(ModelOption.init(rawValue:))
            ?? ModelOption.defaultOption
        selectedModel = model
        hasKey = !keyStore.loadKey(for: model.provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Key & model

    func hasKey(for provider: Provider) -> Bool {
        !keyStore.loadKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func maskedKey(for provider: Provider) -> String {
        let key = keyStore.loadKey(for: provider)
        guard key.count > 8 else { return key.isEmpty ? "还没填" : "已保存" }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }

    func saveKey(_ key: String, for provider: Provider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keyStore.saveKey(trimmed, for: provider)
        refreshHasKey()
    }

    func selectModel(_ model: ModelOption) {
        selectedModel = model
        defaults.set(model.rawValue, forKey: Self.selectedModelKey)
        refreshHasKey()
    }

    private func refreshHasKey() {
        hasKey = hasKey(for: selectedModel.provider)
    }

    // MARK: Chat

    /// 她发一条，等他回。他用空行隔开的几句会变成连发的几个气泡。
    func send(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isLoading else { return }
        append([ChatMessage(sender: .user, content: content)])
        isLoading = true
        defer { isLoading = false }

        do {
            guard let base = systemPromptBase else {
                throw PersonaError.missing(loadError ?? "人设文件")
            }
            var keys: [Provider: String] = [:]
            for provider in Provider.allCases { keys[provider] = keyStore.loadKey(for: provider) }
            let (reply, usedModel) = try await ModelClient.replyWithFallback(
                primary: selectedModel,
                keys: keys,
                systemPrompt: base + "\n\n" + TimeContext.line(),
                messages: messages,
                session: session)
            lastReplyModel = usedModel
            let now = Date()
            append(ModelClient.splitBubbles(reply).map { ChatMessage(sender: .kai, content: $0, date: now) })
        } catch {
            append([ChatMessage(sender: .kai,
                                content: "[消息没发出去: \(error.localizedDescription)]",
                                isError: true)])
        }
    }

    /// 他主动找她：通知响过以后，把那个「?」记进聊天记录，模型下次就能看到。
    /// 她在那之后已经说过话、或者上一条已经是没人回的「?」，就不再加。
    @discardableResult
    func receivePing(_ text: String = PingPlanner.pingText, at date: Date) -> Bool {
        let real = messages.filter { !$0.isError }
        if let last = real.last {
            if let lastDate = last.date, lastDate >= date { return false }
            if last.sender == .kai, last.content == text, !last.isSeed { return false }
        }
        append([ChatMessage(sender: .kai, content: text, date: date)])
        return true
    }

    /// 最后一次有人说话的时间（开场记录没有时间）。
    var lastActivity: Date? {
        messages.last(where: { !$0.isError && $0.date != nil })?.date
    }

    /// 清掉之后的聊天，回到开场记录。
    func resetToOpening() {
        messages = seed
        history.save(messages)
    }

    /// 导出成人能读的 Markdown（设置里「导出聊天记录」用）。
    func exportMarkdown() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeContext.beijing
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines = ["# 和 @/ 的聊天记录", "", "时间是北京时间。开场记录没有时间。", ""]
        var lastStamp = ""
        for message in messages {
            if let date = message.date {
                let stamp = formatter.string(from: date)
                if stamp != lastStamp {
                    lines.append("### \(stamp)")
                    lastStamp = stamp
                }
            }
            let who = message.sender == .user ? "她" : "@/"
            lines.append("**\(who)：** \(message.content)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func append(_ new: [ChatMessage]) {
        messages.append(contentsOf: new)
        history.save(messages)
    }
}
