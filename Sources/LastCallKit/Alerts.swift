import Foundation

public struct AlertSettings: Equatable, Sendable {
    /// Multiples of 5 in 5...100, at most `maxThresholds` per window.
    public var sessionThresholds: [Int]
    public var weeklyThresholds: [Int]
    public var sessionReset: Bool
    public var weeklyReset: Bool

    public static let maxThresholds = 4

    public init(sessionThresholds: [Int] = [], weeklyThresholds: [Int] = [], sessionReset: Bool = false, weeklyReset: Bool = false) {
        self.sessionThresholds = sessionThresholds
        self.weeklyThresholds = weeklyThresholds
        self.sessionReset = sessionReset
        self.weeklyReset = weeklyReset
    }
}

public struct UsageAlert: Equatable, Sendable {
    /// Unique per threshold and window, so each fires once.
    public let key: String
    public let message: String
}

public enum AlertPlanner {
    public static func alerts(
        previous: UsageSnapshot?,
        current: UsageSnapshot,
        settings: AlertSettings,
        fired: Set<String>,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [UsageAlert] {
        var result: [UsageAlert] = []

        if let session = current.fiveHour,
           let threshold = highestReached(settings.sessionThresholds, current: session, previous: previous?.fiveHour) {
            result.append(UsageAlert(
                key: "s\(threshold)|\(windowKey(session))",
                message: sessionMessage(percent: UsageFormat.percent(session.utilization), resetsAt: session.resetsAt, locale: locale, timeZone: timeZone)
            ))
        }

        if let week = current.sevenDay,
           let threshold = highestReached(settings.weeklyThresholds, current: week, previous: previous?.sevenDay) {
            result.append(UsageAlert(
                key: "w\(threshold)|\(windowKey(week))",
                message: weeklyMessage(percent: UsageFormat.percent(week.utilization), resetsAt: week.resetsAt, locale: locale, timeZone: timeZone)
            ))
        }

        if settings.sessionReset,
           let before = previous?.fiveHour, before.utilization >= 80, let beforeReset = before.resetsAt {
            let rolled = current.fiveHour?.resetsAt.map { $0.timeIntervalSince(beforeReset) > 60 } ?? true
            if rolled {
                result.append(UsageAlert(key: "sr|\(minuteKey(beforeReset))", message: sessionResetMessage))
            }
        }

        if settings.weeklyReset,
           let before = previous?.sevenDay, before.utilization >= 80, let beforeReset = before.resetsAt {
            let rolled = current.sevenDay?.resetsAt.map { $0.timeIntervalSince(beforeReset) > 60 } ?? true
            if rolled {
                result.append(UsageAlert(key: "wr|\(minuteKey(beforeReset))", message: weeklyResetMessage))
            }
        }

        return result.filter { !fired.contains($0.key) }
    }

    public static func sessionMessage(percent: Int, resetsAt: Date?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let suffix = resetsAt.map { " Resets at \(UsageFormat.time($0, locale: locale, timeZone: timeZone))." } ?? ""
        return "Session at \(percent)%.\(suffix)"
    }

    public static func weeklyMessage(percent: Int, resetsAt: Date?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let suffix = resetsAt.map { " Resets \(UsageFormat.weekdayAndTime($0, locale: locale, timeZone: timeZone))." } ?? ""
        return "Weekly limit at \(percent)%.\(suffix)"
    }

    public static let sessionResetMessage = "Session reset. Your 5-hour limit is available again."
    public static let weeklyResetMessage = "Weekly limit reset. Your weekly limit is available again."

    /// Only the highest threshold reached fires, so a jump past several sends one alert.
    /// Within the same window as `previous`, a threshold must also have been crossed since then,
    /// so a bell placed below current usage stays quiet.
    private static func highestReached(_ thresholds: [Int], current: UsageWindow, previous: UsageWindow?) -> Int? {
        let floor = previous.flatMap { windowKey($0) == windowKey(current) ? $0.utilization : nil }
        return thresholds.filter { t in Double(t) <= current.utilization && (floor.map { $0 < Double(t) } ?? true) }.max()
    }

    private static func windowKey(_ window: UsageWindow) -> String {
        window.resetsAt.map(minuteKey) ?? "none"
    }

    /// resets_at can wobble by a fraction of a second; whole minutes keep the key stable.
    private static func minuteKey(_ date: Date) -> String {
        String(Int((date.timeIntervalSince1970 / 60).rounded()))
    }
}
