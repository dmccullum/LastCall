import AppIntents

struct GetClaudeUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Claude Usage"
    static let description = IntentDescription("Returns the Claude session and weekly usage with their reset times.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = await UsageModel.shared.summaryText()
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct LastCallShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetClaudeUsageIntent(),
            phrases: [
                "Get Claude usage in \(.applicationName)",
                "Check Claude limits in \(.applicationName)"
            ],
            shortTitle: "Get Claude Usage",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
    }
}
