import DMKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.menuBarDisplay) private var display: MenuBarDisplay = .session
    @AppStorage(SettingsKey.notifySession80) private var session80 = false
    @AppStorage(SettingsKey.notifySession95) private var session95 = false
    @AppStorage(SettingsKey.notifySessionReset) private var sessionReset = false
    @AppStorage(SettingsKey.notifyWeekly80) private var weekly80 = false

    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: loginBinding)
                if loginStatus == .requiresApproval {
                    Text("Approve Last Call in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Menu Bar Shows", selection: $display) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Notifications") {
                Toggle("Session reaches 80%", isOn: $session80)
                Toggle("Session reaches 95%", isOn: $session95)
                Toggle("Session resets", isOn: $sessionReset)
                Toggle("Weekly limit reaches 80%", isOn: $weekly80)
            }
        }
        .formStyle(.grouped)
        .frame(width: DMLayout.settingsWidth)
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
