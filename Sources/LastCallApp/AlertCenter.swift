import Foundation
import LastCallKit
import os
import UserNotifications

/// Posts the threshold notifications and remembers which ones already fired.
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()

    private static let log = Logger(subsystem: "com.danielmccullum.LastCall", category: "notifications")

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
            sessionThresholds: ThresholdList.parse(defaults.string(forKey: SettingsKey.sessionThresholds) ?? ""),
            weeklyThresholds: ThresholdList.parse(defaults.string(forKey: SettingsKey.weeklyThresholds) ?? ""),
            sessionReset: defaults.bool(forKey: SettingsKey.notifySessionReset),
            weeklyReset: defaults.bool(forKey: SettingsKey.notifyWeeklyReset)
        )
    }

    /// Asks for permission the first time a bell or reset is switched on.
    func requestAuthorization() async {
        guard let center else { return }
        let current = await center.notificationSettings()
        guard current.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// The current permission, or nil when running unbundled (e.g. `swift run`).
    func authorizationStatus() async -> UNAuthorizationStatus? {
        guard let center else { return nil }
        return await center.notificationSettings().authorizationStatus
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
                do {
                    try await center.add(UNNotificationRequest(identifier: alert.key, content: content, trigger: nil))
                } catch {
                    Self.log.error("Posting \(alert.key) failed: \(error.localizedDescription)")
                }
            }
        }
    }

    enum TestOutcome {
        case sent
        case denied
        /// Running outside an app bundle (e.g. `swift run`), where notifications don't exist.
        case unbundled
        case failed
    }

    /// Posts `message` as a real notification, asking for permission first if needed.
    @discardableResult
    func sendTest(message: String) async -> TestOutcome {
        guard let center else {
            Self.log.error("Send Test skipped: not running from an app bundle")
            return .unbundled
        }
        await requestAuthorization()
        let status = await center.notificationSettings().authorizationStatus
        Self.log.info("Send Test: authorization status \(status.rawValue)")
        guard status == .authorized || status == .provisional else { return .denied }
        let content = UNMutableNotificationContent()
        content.title = "Last Call"
        content.body = message
        do {
            try await center.add(UNNotificationRequest(identifier: "test-" + UUID().uuidString, content: content, trigger: nil))
            return .sent
        } catch {
            Self.log.error("Send Test failed: \(error.localizedDescription)")
            return .failed
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
