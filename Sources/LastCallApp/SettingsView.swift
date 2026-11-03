import DMKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.menuBarStyle) private var style: MenuBarStyle = .capsules
    @AppStorage(SettingsKey.menuBarDisplay) private var display: MenuBarDisplay = .session
    @AppStorage(SettingsKey.showPaceInMenuBar) private var showPace = false
    @AppStorage(SettingsKey.notifySession80) private var session80 = false
    @AppStorage(SettingsKey.notifySession95) private var session95 = false
    @AppStorage(SettingsKey.notifySessionReset) private var sessionReset = false
    @AppStorage(SettingsKey.notifyWeekly80) private var weekly80 = false

    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
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
            Section("Session Notifications") {
                Toggle("Reaches 80%", isOn: $session80)
                Toggle("Reaches 95%", isOn: $session95)
                Toggle("Resets", isOn: $sessionReset)
            }
            Section("Weekly Notifications") {
                Toggle("Reaches 80%", isOn: $weekly80)
            }
        }
        .formStyle(.grouped)
        // Narrower than DMLayout.settingsWidth (500): Last Call has a few short rows.
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: session80) { _, on in if on { AlertCenter.shared.requestAuthorization() } }
        .onChange(of: session95) { _, on in if on { AlertCenter.shared.requestAuthorization() } }
        .onChange(of: sessionReset) { _, on in if on { AlertCenter.shared.requestAuthorization() } }
        .onChange(of: weekly80) { _, on in if on { AlertCenter.shared.requestAuthorization() } }
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            openAtLogin = loginStatus == .enabled
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
