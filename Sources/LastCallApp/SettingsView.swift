import DMKit
import LastCallKit
import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(SettingsKey.menuBarStyle) private var style: MenuBarStyle = .capsules
    @AppStorage(SettingsKey.menuBarDisplay) private var display: MenuBarDisplay = .session
    @AppStorage(SettingsKey.showPaceInMenuBar) private var showPace = false
    @AppStorage(SettingsKey.showAPIEquivalent) private var showAPIEquivalent = false

    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("Notifications", systemImage: "bell") { NotificationsSettings() }
        }
    }

    private var general: some View {
        Form {
            Section("General") {
                Toggle("Open at Login", isOn: loginBinding)
                if loginStatus == .requiresApproval {
                    Text("Approve Last Call in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Menu Bar") {
                LabeledContent("Style") {
                    HStack(spacing: 10) {
                        ForEach(MenuBarStyle.allCases) { option in
                            StyleTile(style: option, showPace: showPace, isSelected: style == option) { style = option }
                        }
                    }
                }
                Picker("Shows", selection: $display) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $showPace) {
                    Text("Show Pace")
                    Text("Marks how much of each window has passed.")
                }
            }
            Section {
                Toggle("Show in Popover", isOn: $showAPIEquivalent)
            } header: {
                HStack(spacing: 6) {
                    Text("API Equivalent")
                    Text("Beta")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .background(.quaternary, in: .capsule)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Estimated from Claude Code transcripts on this Mac at API list prices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Reads ~/.claude/projects. Excludes claude.ai, the Claude apps and other devices. Prices are built into Last Call and can go out of date.")
            }
        }
        .formStyle(.grouped)
        // Narrower than DMLayout.settingsWidth (500): Last Call has a few short rows.
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: showAPIEquivalent) { _, on in if on { Task { await UsageModel.shared.scanCosts() } } }
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            openAtLogin = loginStatus == .enabled
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        }
        .alert("Couldn’t Change Open at Login", isPresented: Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })) {
            Button("OK") { loginError = nil }
        } message: {
            Text(loginError ?? "")
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { openAtLogin },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    loginError = error.localizedDescription
                }
                loginStatus = SMAppService.mainApp.status
                openAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
            }
        )
    }
}

/// A selectable preview of a menu bar style, drawn with the real menu bar image.
private struct StyleTile: View {
    let style: MenuBarStyle
    let showPace: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: MenuBarIcon.image(
                    session: 0.35,
                    weekly: 0.55,
                    sessionPace: showPace ? 0.6 : nil,
                    weeklyPace: showPace ? 0.75 : nil,
                    style: style
                ))
                .resizable()
                // Exactly 2x, so both styles keep their menu bar proportions to each other.
                .frame(width: style == .rings ? 40 : 36, height: style == .rings ? 36 : 28)
                .foregroundStyle(.primary)
                .frame(width: 64, height: 48)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                }
                Text(style.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NotificationsSettings: View {
    @AppStorage(SettingsKey.sessionThresholds) private var sessionText = ""
    @AppStorage(SettingsKey.weeklyThresholds) private var weeklyText = ""
    @AppStorage(SettingsKey.notifySessionReset) private var sessionReset = false
    @AppStorage(SettingsKey.notifyWeeklyReset) private var weeklyReset = false

    @State private var notificationStatus: UNAuthorizationStatus?

    private var model: UsageModel { UsageModel.shared }
    private var session: [Int] { ThresholdList.parse(sessionText) }
    private var weekly: [Int] { ThresholdList.parse(weeklyText) }

    private var sessionBinding: Binding<[Int]> {
        Binding(get: { session }, set: { sessionText = ThresholdList.format($0) })
    }

    private var weeklyBinding: Binding<[Int]> {
        Binding(get: { weekly }, set: { weeklyText = ThresholdList.format($0) })
    }

    var body: some View {
        Form {
            if notificationStatus == .denied {
                Section {
                    LabeledContent {
                        Button("Open System Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.danielmccullum.LastCall") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } label: {
                        Text("Notifications are off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                header("Current Session", model.snapshot?.fiveHour?.utilization)
                BellBar(name: "Session", thresholds: sessionBinding, utilization: model.snapshot?.fiveHour?.utilization)
                Toggle("Notify When It Resets", isOn: $sessionReset)
            }
            Section {
                header("This Week", model.snapshot?.sevenDay?.utilization)
                BellBar(name: "Weekly", thresholds: weeklyBinding, utilization: model.snapshot?.sevenDay?.utilization)
                Toggle("Notify When It Resets", isOn: $weeklyReset)
            }
            Section("Next Notification") {
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(nextMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(nextMessage)
                    Spacer(minLength: 8)
                    Button("Send Test") {
                        let message = nextMessage
                        Task {
                            await AlertCenter.shared.sendTest(message: message)
                            notificationStatus = await AlertCenter.shared.authorizationStatus()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay { FloatingBellPill() }
        // Same width as the General tab.
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: sessionText) { old, new in
            if ThresholdList.parse(old).isEmpty && !ThresholdList.parse(new).isEmpty { requestNotifications() }
        }
        .onChange(of: weeklyText) { old, new in
            if ThresholdList.parse(old).isEmpty && !ThresholdList.parse(new).isEmpty { requestNotifications() }
        }
        .onChange(of: sessionReset) { _, on in if on { requestNotifications() } }
        .onChange(of: weeklyReset) { _, on in if on { requestNotifications() } }
        .onAppear { refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshNotificationStatus()
        }
    }

    private func header(_ title: String, _ utilization: Double?) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let utilization {
                Text("\(UsageFormat.percent(utilization))% used")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The nearest bell above current usage in either window, else a reset, else a note that none are set.
    private var nextMessage: String {
        let snapshot = model.snapshot
        let sessionUsed = snapshot?.fiveHour?.utilization ?? 0
        let weeklyUsed = snapshot?.sevenDay?.utilization ?? 0
        var candidates: [(distance: Double, message: String)] = []
        if let value = session.first(where: { Double($0) > sessionUsed }) {
            candidates.append((Double(value) - sessionUsed, AlertPlanner.sessionMessage(percent: value, resetsAt: snapshot?.fiveHour?.resetsAt)))
        }
        if let value = weekly.first(where: { Double($0) > weeklyUsed }) {
            candidates.append((Double(value) - weeklyUsed, AlertPlanner.weeklyMessage(percent: value, resetsAt: snapshot?.sevenDay?.resetsAt)))
        }
        if let next = candidates.min(by: { $0.distance < $1.distance }) { return next.message }
        if sessionReset { return AlertPlanner.sessionResetMessage }
        if weeklyReset { return AlertPlanner.weeklyResetMessage }
        return "No bells set."
    }

    private func refreshNotificationStatus() {
        Task { notificationStatus = await AlertCenter.shared.authorizationStatus() }
    }

    private func requestNotifications() {
        Task {
            await AlertCenter.shared.requestAuthorization()
            notificationStatus = await AlertCenter.shared.authorizationStatus()
        }
    }
}
