import AppKit
import DMKit
import SwiftUI

@main
struct LastCallApp: App {
    private let model = UsageModel.shared

    init() {
        UsageModel.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
        .commands {
            AboutCommands(appName: "Last Call")
        }

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

/// Brings an LSUIElement app’s window forward; without this a new window opens behind the frontmost app.
@MainActor
func activateApp() {
    NSApp.activate()
}
