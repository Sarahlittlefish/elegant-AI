import Foundation

/// 谁发的：user = 她，kai = 对方（页面上只显示「@/」）。
enum Sender: String, Codable {
    case user
    case kai
}

/// 一条聊天消息。开场记录没有时间（date = nil），之后的每条都带发送时间。
struct ChatMessage: Identifiable, Codable, Equatable {
    var id: String
    var sender: Sender
    var content: String
    var date: Date?
    /// 「消息没发出去」这种提示：显示给她看，但不发给模型。
    var isError: Bool
    /// 开场聊天记录（seed_history.json 原文）。
    var isSeed: Bool

    init(id: String = UUID().uuidString,
         sender: Sender,
         content: String,
         date: Date? = Date(),
         isError: Bool = false,
         isSeed: Bool = false) {
        self.id = id
        self.sender = sender
        self.content = content
        self.date = date
        self.isError = isError
        self.isSeed = isSeed
    }
}

/// seed_history.json 里的一条（和网页版 seedHistory.ts 一字不差）。
struct SeedMessage: Codable, Equatable {
    var sender: Sender
    var content: String
}

enum SeedHistory {
    /// 把开场记录变成聊天消息。
    static func messages(from seed: [SeedMessage]) -> [ChatMessage] {
        seed.enumerated().map { index, item in
            ChatMessage(id: "seed_\(index)", sender: item.sender, content: item.content,
                        date: nil, isError: false, isSeed: true)
        }
    }

    static func decode(_ data: Data) throws -> [SeedMessage] {
        try JSONDecoder().decode([SeedMessage].self, from: data)
    }
}
