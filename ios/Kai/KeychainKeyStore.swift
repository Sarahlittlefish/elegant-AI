import Foundation
import Security

/// 智谱 Key 存在 iPad 的钥匙串里：只在这台 iPad 上，不在代码里，不会上 GitHub。
/// 每 7 天用 Xcode 重装一次也不会丢，不用重新填。
struct KeychainKeyStore: KeyStoring {
    var service = "com.sarahlittlefish.kaichat"
    var account = "zhipu_api_key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func loadKey() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return "" }
        return key
    }

    func saveKey(_ key: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !key.isEmpty else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

extension ChatStore {
    /// app 里真正用的那个：聊天记录存在 Application Support/chat_history.json，
    /// 人设、档案、开场记录从 app 里打包的文件读。
    static func live() -> ChatStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let historyURL = support.appendingPathComponent("chat_history.json")

        var seed: [SeedMessage] = []
        if let url = Bundle.main.url(forResource: "seed_history", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? SeedHistory.decode(data) {
            seed = decoded
        }

        let prompt = Result { try Persona.loadFromBundle() }
        return ChatStore(history: HistoryFile(url: historyURL),
                         seed: seed,
                         keyStore: KeychainKeyStore(),
                         systemPrompt: prompt)
    }
}
