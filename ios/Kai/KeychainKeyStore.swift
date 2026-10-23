import Foundation
import Security

/// 魔搭令牌和智谱 Key 都存在 iPad 的钥匙串里：只在这台 iPad 上，不在代码里，不会上 GitHub。
/// 每 7 天用 Xcode 重装一次也不会丢，不用重新填。智谱 Key 还用原来那个位置，升级后不用重填。
struct KeychainKeyStore: KeyStoring {
    var service = "com.sarahlittlefish.kaichat"

    static func account(for provider: Provider) -> String {
        switch provider {
        case .zhipu: return "zhipu_api_key"
        case .modelscope: return "modelscope_token"
        }
    }

    private func baseQuery(_ provider: Provider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account(for: provider),
        ]
    }

    func loadKey(for provider: Provider) -> String {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return "" }
        return key
    }

    func saveKey(_ key: String, for provider: Provider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        guard !key.isEmpty else { return }
        var attributes = baseQuery(provider)
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
