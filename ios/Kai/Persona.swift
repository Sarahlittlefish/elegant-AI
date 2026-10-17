import Foundation

/// 系统提示词 = kai_persona_v2.md 原文 + kai_profile.md 原文（和网页版 loadPersona.ts 完全一样的处理），
/// 后面再接一行当前的布拉格 / 北京时间，让他不再乱报时间。
enum Persona {
    /// 和 loadPersona.ts 相同：去掉 BOM 和首尾空白，去掉结尾的「听懂回复ok」（如果有），
    /// 档案存在就用一个空行接在人设后面。人设和档案的正文一个字不改。
    static func systemPrompt(persona rawPersona: String, profile rawProfile: String?) -> String {
        var persona = stripBOM(rawPersona).trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = persona.range(of: #"\s*听懂回复\s*ok\s*$"#,
                                     options: [.regularExpression, .caseInsensitive]) {
            persona.removeSubrange(range)
        }
        persona = persona.trimmingCharacters(in: .whitespacesAndNewlines)

        let profile = stripBOM(rawProfile ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return profile.isEmpty ? persona : persona + "\n\n" + profile
    }

    /// 从 app 里打包的两个文件读出系统提示词。
    static func loadFromBundle(_ bundle: Bundle = .main) throws -> String {
        guard let personaURL = bundle.url(forResource: "kai_persona_v2", withExtension: "md") else {
            throw PersonaError.missing("kai_persona_v2.md")
        }
        let persona = try String(contentsOf: personaURL, encoding: .utf8)
        var profile: String?
        if let profileURL = bundle.url(forResource: "kai_profile", withExtension: "md") {
            profile = try String(contentsOf: profileURL, encoding: .utf8)
        }
        return systemPrompt(persona: persona, profile: profile)
    }

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}

enum PersonaError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name): return "app 里找不到人设文件 \(name)"
        }
    }
}

/// 当前时间：每次发消息都附在系统提示词最后一行。
enum TimeContext {
    static let prague = TimeZone(identifier: "Europe/Prague")!
    static let beijing = TimeZone(identifier: "Asia/Shanghai")!

    static func line(now: Date = Date()) -> String {
        "（当前时间：布拉格 \(format(now, in: prague))；北京 \(format(now, in: beijing))）"
    }

    static func format(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "M月d日 EEEE HH:mm"
        return formatter.string(from: date)
    }
}
