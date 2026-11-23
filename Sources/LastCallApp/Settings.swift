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
    static let showClaude = "showClaude"
    static let showCodex = "showCodex"
    static let menuBarItems = "menuBarItems"
    static let selectedService = "selectedService"
    static let codexMenuBarStyle = "codexMenuBarStyle"
    /// The letter on each menu bar item while both services are on.
    static let claudeLabel = "claudeLabel"
    static let codexLabel = "codexLabel"
    static let letterInsideRings = "letterInsideRings"
    static let codexSessionThresholds = "codexSessionThresholds"
    static let codexWeeklyThresholds = "codexWeeklyThresholds"
    static let notifyCodexSessionReset = "notifyCodexSessionReset"
    static let notifyCodexWeeklyReset = "notifyCodexWeeklyReset"
}

enum Service: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// The service a combined menu bar item and popover show: `selected`, unless it is off.
    static func shown(selected: Service, claudeOn: Bool, codexOn: Bool) -> Service {
        switch (claudeOn, codexOn) {
        case (true, false): .claude
        case (false, true): .codex
        default: selected
        }
    }
}

/// A menu bar item: one item that shows the selected service, or one fixed to a service.
enum MenuBarItem: Equatable {
    case combined
    case service(Service)
}

/// The settings key names and defaults for one service, so views and `AlertCenter`
/// don’t switch on strings. Claude’s keys keep the names they had before Codex.
struct ServiceSettings {
    let service: Service

    init(_ service: Service) { self.service = service }

    var enabledKey: String { service == .claude ? SettingsKey.showClaude : SettingsKey.showCodex }
    var styleKey: String { service == .claude ? SettingsKey.menuBarStyle : SettingsKey.codexMenuBarStyle }
    var sessionThresholdsKey: String { service == .claude ? SettingsKey.sessionThresholds : SettingsKey.codexSessionThresholds }
    var weeklyThresholdsKey: String { service == .claude ? SettingsKey.weeklyThresholds : SettingsKey.codexWeeklyThresholds }
    var sessionResetKey: String { service == .claude ? SettingsKey.notifySessionReset : SettingsKey.notifyCodexSessionReset }
    var weeklyResetKey: String { service == .claude ? SettingsKey.notifyWeeklyReset : SettingsKey.notifyCodexWeeklyReset }

    /// Different defaults give the two separate menu bar items different silhouettes.
    var defaultStyle: MenuBarStyle { service == .claude ? .capsules : .rings }

    /// The `service` string `AlertPlanner` uses for its key prefix.
    var plannerName: String { service.rawValue }

    func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? (service == .claude)
    }

    func style(_ defaults: UserDefaults = .standard) -> MenuBarStyle {
        defaults.string(forKey: styleKey).flatMap(MenuBarStyle.init(rawValue:)) ?? defaultStyle
    }

    func alertSettings(_ defaults: UserDefaults = .standard) -> AlertSettings {
        AlertSettings(
            sessionThresholds: ThresholdList.parse(defaults.string(forKey: sessionThresholdsKey) ?? ""),
            weeklyThresholds: ThresholdList.parse(defaults.string(forKey: weeklyThresholdsKey) ?? ""),
            sessionReset: defaults.bool(forKey: sessionResetKey),
            weeklyReset: defaults.bool(forKey: weeklyResetKey)
        )
    }
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
        // Codex is on from the start only when Codex has left session logs on this Mac.
        if defaults.object(forKey: SettingsKey.showClaude) == nil {
            defaults.set(true, forKey: SettingsKey.showClaude)
        }
        if defaults.object(forKey: SettingsKey.showCodex) == nil {
            let sessions = CodexUsageReader.defaultHome.appending(path: "sessions", directoryHint: .isDirectory)
            defaults.set(FileManager.default.fileExists(atPath: sessions.path), forKey: SettingsKey.showCodex)
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
    /// One full ring for the 5-hour session; no weekly.
    case ring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capsules: "Capsules"
        case .rings: "Rings"
        case .ring: "Ring"
        }
    }

    /// Styles with room for the service letter in the middle.
    var holdsLetter: Bool { self != .capsules }
}

enum MenuBarItems: String, CaseIterable, Identifiable {
    case combined
    case separate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: "One Item"
        case .separate: "One per Service"
        }
    }
}
