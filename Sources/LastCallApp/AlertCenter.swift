import Foundation
import LastCallKit
import UserNotifications

/// Posts the threshold notifications and remembers which ones already fired.
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()

    private var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private var center: UNUserNotificationCenter? {
        guard isBundled else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }

    var settings: AlertSettings {
        let defaults = UserDefaults.standard
        return AlertSettings(
            session80: defaults.bool(forKey: SettingsKey.notifySession80),
            session95: defaults.bool(forKey: SettingsKey.notifySession95),
            sessionReset: defaults.bool(forKey: SettingsKey.notifySessionReset),
            weekly80: defaults.bool(forKey: SettingsKey.notifyWeekly80)
        )
    }

    /// Asks for permission the first time a toggle is switched on.
    func requestAuthorization() {
        guard let center else { return }
        Task {
            let current = await center.notificationSettings()
            guard current.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func evaluate(previous: UsageSnapshot?, current: UsageSnapshot) {
        let settings = settings
        guard settings != AlertSettings(), let center else { return }
        let defaults = UserDefaults.standard
        let firedList = defaults.stringArray(forKey: SettingsKey.firedAlerts) ?? []
        let alerts = AlertPlanner.alerts(previous: previous, current: current, settings: settings, fired: Set(firedList))
        guard !alerts.isEmpty else { return }
        defaults.set(Array((firedList + alerts.map(\.key)).suffix(60)), forKey: SettingsKey.firedAlerts)

        Task {
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = "Last Call"
                content.body = alert.message
                try? await center.add(UNNotificationRequest(identifier: alert.key, content: content, trigger: nil))
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
