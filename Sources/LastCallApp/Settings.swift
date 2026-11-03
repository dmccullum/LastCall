import Foundation

enum SettingsKey {
    static let menuBarDisplay = "menuBarDisplay"
    static let menuBarStyle = "menuBarStyle"
    static let showPaceInMenuBar = "showPaceInMenuBar"
    static let notifySession80 = "notifySession80"
    static let notifySession95 = "notifySession95"
    static let notifySessionReset = "notifySessionReset"
    static let notifyWeekly80 = "notifyWeekly80"
    static let firedAlerts = "firedAlerts"
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
