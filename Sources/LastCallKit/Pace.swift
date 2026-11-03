import Foundation

public enum UsageWindowKind: Sendable {
    case fiveHour
    case weekly

    public var duration: TimeInterval {
        switch self {
        case .fiveHour: 5 * 3600
        case .weekly: 7 * 86400
        }
    }
}

public enum Pace: Equatable, Sendable {
    case ahead
    case onPace
    case behind

    public var title: String {
        switch self {
        case .ahead: "Ahead of pace"
        case .onPace: "On pace"
        case .behind: "Behind pace"
        }
    }
}

public enum PaceMath {
    /// Percentage points either side of the elapsed fraction that still count as on pace.
    public static let tolerance = 5.0

    /// The fraction (0 to 1) of the window that has passed: 1 − (resetsAt − now) / duration.
    public static func elapsedFraction(resetsAt: Date, now: Date, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(1 - remaining / duration, 0), 1)
    }

    public static func elapsedFraction(resetsAt: Date, now: Date, kind: UsageWindowKind) -> Double {
        elapsedFraction(resetsAt: resetsAt, now: now, duration: kind.duration)
    }

    /// Ahead when utilization% is more than 5 points over elapsed%, behind when more than 5 under.
    public static func pace(utilizationPercent: Double, elapsedFraction: Double) -> Pace {
        let elapsedPercent = elapsedFraction * 100
        if utilizationPercent > elapsedPercent + tolerance { return .ahead }
        if utilizationPercent < elapsedPercent - tolerance { return .behind }
        return .onPace
    }
}
