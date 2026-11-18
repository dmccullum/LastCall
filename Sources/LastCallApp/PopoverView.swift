import AppKit
import LastCallKit
import SwiftUI

struct PopoverView: View {
    let item: MenuBarItem

    @State private var isShown = false
    @State private var copied = false
    @AppStorage(SettingsKey.showAPIEquivalent) private var showAPIEquivalent = false
    @AppStorage(SettingsKey.selectedService) private var selectedService: Service = .claude
    @AppStorage(SettingsKey.showClaude) private var showClaude = true
    @AppStorage(SettingsKey.showCodex) private var showCodex = false
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var service: Service {
        switch item {
        case .service(let service): service
        case .combined: Service.shown(selected: selectedService, claudeOn: showClaude, codexOn: showCodex)
        }
    }

    private var model: UsageModel { .model(for: service) }

    private var showsPicker: Bool { item == .combined && showClaude && showCodex }

    /// Codex numbers are only as fresh as the last Codex request, so its footer always shows.
    private var showsFooter: Bool {
        guard model.lastUpdated != nil else { return false }
        return service == .codex || model.problem != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                if showsPicker {
                    servicePicker
                } else if case .service = item {
                    header
                }
                content
            }
            .padding(16)
            // Claude’s update time only matters when the numbers are stale.
            if showsFooter {
                Divider()
                footer
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            Divider()
            actions
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: 300)
        .background { shortcuts }
        .onAppear { shown() }
        .onChange(of: selectedService) { if isShown { shown() } }
        .onDisappear { isShown = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow)?.title.isEmpty == true { shown() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if (note.object as? NSWindow)?.title.isEmpty == true { isShown = false }
        }
    }

    private func shown() {
        isShown = true
        let model = model
        Task {
            await model.refreshIfStale(after: model.service == .codex ? 10 : 60)
            await model.scanCosts()
        }
    }

    // MARK: Service switch

    private var servicePicker: some View {
        Picker("Service", selection: $selectedService) {
            ForEach(Service.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// ⌘1 and ⌘2 pick Claude and Codex while the popover is open.
    @ViewBuilder private var shortcuts: some View {
        if showsPicker {
            ZStack {
                Button("Show Claude") { selectedService = .claude }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Show Codex") { selectedService = .codex }
                    .keyboardShortcut("2", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(service.title).font(.headline)
            Spacer()
            if let plan = model.planText {
                Text(plan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.problem == .signedOut {
            if service == .codex { noCodexData } else { signedOut }
        } else if let snapshot = model.snapshot {
            TimelineView(PopoverSchedule(live: isShown)) { timeline in
                VStack(alignment: .leading, spacing: 16) {
                    UsageRow(
                        title: "Current Session",
                        window: snapshot.fiveHour,
                        kind: .fiveHour,
                        now: timeline.date,
                        emptyText: "No active session",
                        cost: showAPIEquivalent ? model.sessionCost : nil
                    )
                    UsageRow(
                        title: "This Week",
                        window: snapshot.sevenDay,
                        kind: .weekly,
                        now: timeline.date,
                        emptyText: "No usage yet",
                        cost: showAPIEquivalent ? model.weeklyCost : nil
                    )
                    if let opus = snapshot.sevenDayOpus {
                        UsageRow(title: "Opus This Week", window: opus, kind: .weekly, now: timeline.date, emptyText: "", compact: true)
                    }
                    if let sonnet = snapshot.sevenDaySonnet {
                        UsageRow(title: "Sonnet This Week", window: sonnet, kind: .weekly, now: timeline.date, emptyText: "", compact: true)
                    }
                    if case .message(let text) = model.problem {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(model.problem == nil ? 1 : 0.55)
            }
        } else if case .message(let text) = model.problem {
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking usage…").foregroundStyle(.secondary)
            }
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to Claude Code to see your limits.")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Button(copied ? "Copied" : "Copy Sign-In Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("claude /login", forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            }
            Text("Run it in Terminal, then Last Call updates on its own.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noCodexData: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Codex usage found.")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Last Call reads the limits Codex records in ~/.codex/sessions. Send one request in Codex, and they appear here within a minute.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            TimelineView(PopoverSchedule(live: isShown)) { timeline in
                Text(footerText(now: timeline.date))
                    .monospacedDigit()
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func footerText(now: Date) -> String {
        guard let updated = model.lastUpdated else { return "Not updated yet" }
        return service == .codex ? UsageFormat.codexAsOf(updated, now: now) : UsageFormat.updated(updated, now: now)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Settings…", shortcut: "⌘,") {
                activateApp()
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "About Last Call", shortcut: nil) {
                activateApp()
                openWindow(id: "about")
            }
            MenuRow(title: "Quit Last Call", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

private struct UsageRow: View {
    let title: String
    let window: UsageWindow?
    let kind: UsageWindowKind
    let now: Date
    let emptyText: String
    var compact = false
    var cost: CostEstimate?

    private var utilization: Double { window?.utilization ?? 0 }

    private var elapsed: Double? {
        window?.resetsAt.map { PaceMath.elapsedFraction(resetsAt: $0, now: now, kind: kind) }
    }

    private var resetText: String {
        guard let reset = window?.resetsAt else { return emptyText }
        switch kind {
        case .fiveHour: return UsageFormat.resetsIn(reset, now: now)
        case .weekly: return UsageFormat.resetsOn(reset)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(title)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(UsageFormat.percent(utilization))%")
                    .font(compact ? .title3 : .largeTitle)
                    .fontWeight(.semibold)
                    .fontDesign(compact ? .default : .rounded)
                    .monospacedDigit()
                Text("used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            UsageBar(title: title, utilization: utilization, elapsed: elapsed, height: compact ? 5 : 8)
            if !compact, let elapsed {
                Text(PaceMath.pace(utilizationPercent: utilization, elapsedFraction: elapsed).title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !compact, let cost {
                Text(cost.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Estimated from Claude Code transcripts on this Mac at API list prices. Doesn’t include claude.ai or other devices.")
            }
        }
    }
}

/// Ticks every 30 seconds while the popover is open and doesn’t tick at all while it’s closed.
private struct PopoverSchedule: TimelineSchedule {
    var live: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        if live {
            return AnySequence(PeriodicTimelineSchedule(from: startDate, by: 30).entries(from: startDate, mode: mode))
        }
        return AnySequence([startDate])
    }
}
