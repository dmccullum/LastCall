import Foundation

public struct AlertSettings: Equatable, Sendable {
    public var session80: Bool
    public var session95: Bool
    public var sessionReset: Bool
    public var weekly80: Bool

    public init(session80: Bool = false, session95: Bool = false, sessionReset: Bool = false, weekly80: Bool = false) {
        self.session80 = session80
        self.session95 = session95
        self.sessionReset = sessionReset
        self.weekly80 = weekly80
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

        if let session = current.fiveHour {
            let window = windowKey(session)
            let reset = session.resetsAt.map { UsageFormat.time($0, locale: locale, timeZone: timeZone) }
            let suffix = reset.map { " Resets at \($0)." } ?? ""
            let percent = UsageFormat.percent(session.utilization)
            let at95 = settings.session95 && session.utilization >= 95
            if at95 {
                result.append(UsageAlert(key: "s95|\(window)", message: "Session at \(percent)%.\(suffix)"))
            }
            // A jump straight past 95 sends one alert, not two.
            if settings.session80 && session.utilization >= 80 && !at95 {
                result.append(UsageAlert(key: "s80|\(window)", message: "Session at \(percent)%.\(suffix)"))
            }
        }

        if settings.sessionReset,
           let before = previous?.fiveHour, before.utilization >= 80, let beforeReset = before.resetsAt {
            let rolled = current.fiveHour?.resetsAt.map { $0.timeIntervalSince(beforeReset) > 60 } ?? true
            if rolled {
                result.append(UsageAlert(
                    key: "sr|\(minuteKey(beforeReset))",
                    message: "Session reset. Your 5-hour limit is available again."
                ))
            }
        }

        if settings.weekly80, let week = current.sevenDay, week.utilization >= 80 {
            let suffix = week.resetsAt.map { " Resets \(UsageFormat.weekdayAndTime($0, locale: locale, timeZone: timeZone))." } ?? ""
            result.append(UsageAlert(
                key: "w80|\(windowKey(week))",
                message: "Weekly limit at \(UsageFormat.percent(week.utilization))%.\(suffix)"
            ))
        }

        return result.filter { !fired.contains($0.key) }
    }

    private static func windowKey(_ window: UsageWindow) -> String {
        window.resetsAt.map(minuteKey) ?? "none"
    }

    /// resets_at can wobble by a fraction of a second; whole minutes keep the key stable.
    private static func minuteKey(_ date: Date) -> String {
        String(Int((date.timeIntervalSince1970 / 60).rounded()))
    }
}
