import AppKit
import DMKit
import SwiftUI

@main
struct LastCallApp: App {
    @AppStorage(SettingsKey.showClaude) private var showClaude = true
    @AppStorage(SettingsKey.showCodex) private var showCodex = false
    @AppStorage(SettingsKey.menuBarItems) private var menuBarItems: MenuBarItems = .combined
    @AppStorage(SettingsKey.selectedService) private var selectedService: Service = .claude

    init() {
        SettingsMigration.run()
        UsageModel.claude.followSettings()
        UsageModel.codex.followSettings()
    }

    /// Combined mode: the only item, showing the selected service. Separate mode: the Claude item.
    private var firstItem: MenuBarItem { menuBarItems == .combined ? .combined : .service(.claude) }

    var body: some Scene {
        MenuBarExtra(isInserted: firstItemInserted) {
            PopoverView(item: firstItem)
        } label: {
            MenuBarItemLabel(item: firstItem)
        }
        .menuBarExtraStyle(.window)
        .commands {
            AboutCommands(appName: "Last Call")
        }

        // Exists only in separate mode.
        MenuBarExtra(isInserted: codexItemInserted) {
            PopoverView(item: .service(.codex))
        } label: {
            MenuBarItemLabel(item: .service(.codex))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }

        AboutScene(
            appName: "Last Call",
            links: AboutLinks(
                website: URL(string: "https://github.com/dmccullum/LastCall"),
                sourceCode: URL(string: "https://github.com/dmccullum/LastCall")
            )
        )
    }
}

extension LastCallApp {
    private var firstItemInserted: Binding<Bool> {
        Binding(
            get: { menuBarItems == .combined || showClaude },
            set: { inserted in
                // Dragging an item out of the menu bar turns its service off.
                guard !inserted else { return }
                switch menuBarItems {
                case .combined: turnOff(Service.shown(selected: selectedService, claudeOn: showClaude, codexOn: showCodex))
                case .separate: turnOff(.claude)
                }
            }
        )
    }

    private var codexItemInserted: Binding<Bool> {
        Binding(
            get: { menuBarItems == .separate && showCodex },
            set: { inserted in
                guard !inserted, menuBarItems == .separate else { return }
                turnOff(.codex)
            }
        )
    }

    /// Leaves at least one service on.
    private func turnOff(_ service: Service) {
        switch service {
        case .claude: if showCodex { showClaude = false }
        case .codex: if showClaude { showCodex = false }
        }
    }
}

/// Brings an LSUIElement app’s window forward; without this a new window opens behind the frontmost app.
@MainActor
func activateApp() {
    NSApp.activate()
}
