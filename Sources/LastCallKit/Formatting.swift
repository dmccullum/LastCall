import Foundation

public enum UsageFormat {
    public static func percent(_ utilization: Double) -> Int {
        Int(min(max(utilization, 0), 100).rounded())
    }

    /// “Resets in 2 hr 13 min”; under a minute, “Resets in less than a minute”.
    public static func resetsIn(_ reset: Date, now: Date, locale: Locale = .current) -> String {
        "Resets in " + countdown(reset.timeIntervalSince(now), locale: locale)
    }

    /// “2 hr 13 min”, “1 day 3 hr”, or “less than a minute”. Whole minutes, rounded down.
    public static func countdown(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 1 else { return "less than a minute" }
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        var parts: [(Int, Duration.UnitsFormatStyle.Unit)] = []
        if days > 0 { parts.append((days, .days)) }
        if hours > 0 { parts.append((hours, .hours)) }
        // With days showing, minutes are noise.
        if mins > 0 && days == 0 { parts.append((mins, .minutes)) }
        return parts.map { value, unit in
            Duration.seconds(value * unit.seconds).formatted(
                Duration.UnitsFormatStyle(allowedUnits: [unit], width: .abbreviated).locale(locale)
            )
        }.joined(separator: " ")
    }

    /// “Resets Thu 9:00 AM”.
    public static func resetsOn(_ reset: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "Resets " + weekdayAndTime(reset, locale: locale, timeZone: timeZone)
    }

    /// “Resets at 3:40 PM”.
    public static func resetsAt(_ reset: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "Resets at " + time(reset, locale: locale, timeZone: timeZone)
    }

    public static func time(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
    }

    public static func weekdayAndTime(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated).hour().minute())
    }

    /// “Updated just now” under a minute, then “Updated 1 min ago”.
    public static func updated(_ date: Date, now: Date, locale: Locale = .current) -> String {
        let age = now.timeIntervalSince(date)
        if age < 60 { return "Updated just now" }
        return "Updated \(countdown(age, locale: locale)) ago"
    }

    /// “Session 42%, resets 3:40 PM. Week 18%, resets Thu 9:00 AM.”
    public static func summary(
        _ snapshot: UsageSnapshot,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var sentences: [String] = []
        if let window = snapshot.fiveHour {
            var text = "Session \(percent(window.utilization))%"
            if let reset = window.resetsAt { text += ", resets " + time(reset, locale: locale, timeZone: timeZone) }
            sentences.append(text + ".")
        }
        if let window = snapshot.sevenDay {
            var text = "Week \(percent(window.utilization))%"
            if let reset = window.resetsAt { text += ", resets " + weekdayAndTime(reset, locale: locale, timeZone: timeZone) }
            sentences.append(text + ".")
        }
        return sentences.isEmpty ? "No usage windows are active." : sentences.joined(separator: " ")
    }
}

private extension Duration.UnitsFormatStyle.Unit {
    var seconds: Int {
        switch self {
        case .days: 86400
        case .hours: 3600
        default: 60
        }
    }
}
