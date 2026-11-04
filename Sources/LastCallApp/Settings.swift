import Foundation
import LastCallKit

enum SettingsKey {
    static let menuBarDisplay = "menuBarDisplay"
    static let menuBarStyle = "menuBarStyle"
    static let showPaceInMenuBar = "showPaceInMenuBar"
    static let showAPIEquivalent = "showAPIEquivalent"
    /// Comma-separated percentages, e.g. "80,95".
    static let sessionThresholds = "sessionThresholds"
    static let weeklyThresholds = "weeklyThresholds"
    static let notifySessionReset = "notifySessionReset"
    static let notifyWeeklyReset = "notifyWeeklyReset"
    // Replaced by the threshold lists; read once by `SettingsMigration`.
    static let legacyNotifySession80 = "notifySession80"
    static let legacyNotifySession95 = "notifySession95"
    static let legacyNotifyWeekly80 = "notifyWeekly80"
    static let firedAlerts = "firedAlerts"
}

/// Bell percentages as stored: multiples of 5 in 5...100, sorted, at most four.
enum ThresholdList {
    static func parse(_ text: String) -> [Int] {
        normalized(text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    static func format(_ values: [Int]) -> String {
        normalized(values).map(String.init).joined(separator: ",")
    }

    static func normalized(_ values: [Int]) -> [Int] {
        let valid = Set(values.filter { (5...100).contains($0) && $0 % 5 == 0 })
        return Array(valid.sorted().prefix(AlertSettings.maxThresholds))
    }
}

enum SettingsMigration {
    /// Turns the old fixed toggles into threshold lists, once, then deletes them.
    static func run(_ defaults: UserDefaults = .standard) {
        if defaults.object(forKey: SettingsKey.sessionThresholds) == nil {
            var values: [Int] = []
            if defaults.bool(forKey: SettingsKey.legacyNotifySession80) { values.append(80) }
            if defaults.bool(forKey: SettingsKey.legacyNotifySession95) { values.append(95) }
            defaults.set(ThresholdList.format(values), forKey: SettingsKey.sessionThresholds)
        }
        if defaults.object(forKey: SettingsKey.weeklyThresholds) == nil {
            let values = defaults.bool(forKey: SettingsKey.legacyNotifyWeekly80) ? [80] : []
            defaults.set(ThresholdList.format(values), forKey: SettingsKey.weeklyThresholds)
        }
        for key in [SettingsKey.legacyNotifySession80, SettingsKey.legacyNotifySession95, SettingsKey.legacyNotifyWeekly80] {
            defaults.removeObject(forKey: key)
        }
    }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case session
    case weekly
    case both
    case iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: "Session Percentage"
        case .weekly: "Weekly Percentage"
        case .both: "Both"
        case .iconOnly: "Icon Only"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case capsules
    case rings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capsules: "Capsules"
        case .rings: "Rings"
        }
    }
}
