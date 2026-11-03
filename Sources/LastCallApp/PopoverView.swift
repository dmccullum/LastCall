import AppKit
import LastCallKit
import SwiftUI

struct PopoverView: View {
    let model: UsageModel

    @State private var isShown = false
    @State private var copied = false
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(16)
            // The update time only matters when the numbers are stale.
            if model.problem != nil, model.lastUpdated != nil {
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
        .onAppear { shown() }
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
        Task { await model.refreshIfStale(after: 60) }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.problem == .signedOut {
            signedOut
        } else if let snapshot = model.snapshot {
            TimelineView(PopoverSchedule(live: isShown)) { timeline in
                VStack(alignment: .leading, spacing: 16) {
                    UsageRow(
                        title: "Current Session",
                        window: snapshot.fiveHour,
                        kind: .fiveHour,
                        now: timeline.date,
                        emptyText: "No active session"
                    )
                    UsageRow(
                        title: "This Week",
                        window: snapshot.sevenDay,
                        kind: .weekly,
                        now: timeline.date,
                        emptyText: "No usage yet"
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

    // MARK: Footer

    private var footer: some View {
        HStack {
            TimelineView(PopoverSchedule(live: isShown)) { timeline in
                Text(model.lastUpdated.map { UsageFormat.updated($0, now: timeline.date) } ?? "Not updated yet")
                    .monospacedDigit()
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
