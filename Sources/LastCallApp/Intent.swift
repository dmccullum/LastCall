import AppIntents

struct GetClaudeUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Claude Usage"
    static let description = IntentDescription("Returns the Claude session and weekly usage with their reset times.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = await UsageModel.claude.summaryText()
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct GetCodexUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Codex Usage"
    static let description = IntentDescription("Returns the Codex session and weekly usage with their reset times.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = await UsageModel.codex.summaryText()
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
        AppShortcut(
            intent: GetCodexUsageIntent(),
            phrases: [
                "Get Codex usage in \(.applicationName)",
                "Check Codex limits in \(.applicationName)"
            ],
            shortTitle: "Get Codex Usage",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
    }
}
