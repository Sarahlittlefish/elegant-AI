import Foundation

/// 「他偶尔主动找你」的时间怎么挑（纯计算，不碰通知系统）。
///
/// 规则：
/// - 每次她离开 app，只安排下一条：1 到 3 天后的北京时间 19:00–22:00 之间随机一个时刻
///   （就是布拉格的下午，他刚下课；布拉格的傍晚在北京是半夜，不吵她睡觉）。
/// - 她一打开 app 就取消还没响的那条；她不理他，他也不会连着发，只等她下次打开再离开时才排下一条。
/// - 他发的就是一个「?」，和档案里他破冰时的习惯一样；她回了以后，模型在聊天记录里看得到这个「?」。
struct PingPlanner {
    static let pingText = "?"

    var timeZone: TimeZone = TimeContext.beijing
    /// 从 0 点算起的分钟数。
    var windowStartMinutes = 19 * 60
    var windowEndMinutes = 22 * 60
    var dayOffsets: ClosedRange<Int> = 1...3

    func nextPingDate<G: RandomNumberGenerator>(after now: Date, using generator: inout G) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: now)
        let days = Int.random(in: dayOffsets, using: &generator)
        let minute = Int.random(in: windowStartMinutes..<windowEndMinutes, using: &generator)
        let day = calendar.date(byAdding: .day, value: days, to: startOfToday) ?? now
        return calendar.date(byAdding: .minute, value: minute, to: day) ?? day
    }

    func nextPingDate(after now: Date) -> Date {
        var generator = SystemRandomNumberGenerator()
        return nextPingDate(after: now, using: &generator)
    }
}
