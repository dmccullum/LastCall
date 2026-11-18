import LastCallKit
import SwiftUI

/// The label of a menu bar item. Combined items show whichever service is selected.
struct MenuBarItemLabel: View {
    let item: MenuBarItem
    @AppStorage(SettingsKey.selectedService) private var selected: Service = .claude
    @AppStorage(SettingsKey.showClaude) private var showClaude = true
    @AppStorage(SettingsKey.showCodex) private var showCodex = false
    @AppStorage(SettingsKey.menuBarStyle) private var claudeStyle: MenuBarStyle = .capsules
    @AppStorage(SettingsKey.codexMenuBarStyle) private var codexStyle: MenuBarStyle = .rings

    private var service: Service {
        switch item {
        case .service(let service): service
        case .combined: Service.shown(selected: selected, claudeOn: showClaude, codexOn: showCodex)
        }
    }

    var body: some View {
        MenuBarLabel(model: .model(for: service), style: service == .claude ? claudeStyle : codexStyle)
    }
}

struct MenuBarLabel: View {
    let model: UsageModel
    let style: MenuBarStyle
    @AppStorage(SettingsKey.menuBarDisplay) private var display: MenuBarDisplay = .session
    @AppStorage(SettingsKey.showPaceInMenuBar) private var showPace = false
    @State private var now = Date.now

    private var session: Int? { model.snapshot?.fiveHour.map { UsageFormat.percent($0.utilization) } }
    private var weekly: Int? { model.snapshot?.sevenDay.map { UsageFormat.percent($0.utilization) } }

    private var text: String? {
        switch display {
        case .session: session.map { "\($0)%" }
        case .weekly: weekly.map { "\($0)%" }
        case .both:
            if let session, let weekly { "\(session)% · \(weekly)%" } else { (session ?? weekly).map { "\($0)%" } }
        case .iconOnly: nil
        }
    }

    private var accessibilityText: String {
        let name = model.service.title
        switch (session, weekly) {
        case let (session?, weekly?): return "\(name) session \(session) percent, weekly \(weekly) percent"
        case let (session?, nil): return "\(name) session \(session) percent"
        case let (nil, weekly?): return "\(name) weekly \(weekly) percent"
        default:
            guard model.problem == .signedOut else { return "\(name) usage" }
            return model.service == .codex ? "Codex usage, no data" : "Claude usage, signed out"
        }
    }

    var body: some View {
        // MenuBarExtra draws nothing for a TimelineView label, so the label stays a plain
        // Image and a timer moves the pace ticks. Once a minute is finer than a 1 pt tick
        // on a 5-hour window can show.
        icon(now: showPace ? now : nil)
            .onReceive(Timer.publish(every: 60, tolerance: 10, on: .main, in: .common).autoconnect()) { date in
                if showPace { now = date }
            }
            .onChange(of: showPace) { now = .now }
    }

    /// One image holding the capsules and the text, so the item gets the same end padding
    /// as the icon-only items beside it. With `now`, each capsule gets a pace tick.
    private func icon(now: Date?) -> some View {
        let sessionPace = now.flatMap { now in
            model.snapshot?.fiveHour?.resetsAt.map { PaceMath.elapsedFraction(resetsAt: $0, now: now, kind: .fiveHour) }
        }
        let weeklyPace = now.flatMap { now in
            model.snapshot?.sevenDay?.resetsAt.map { PaceMath.elapsedFraction(resetsAt: $0, now: now, kind: .weekly) }
        }
        return Image(nsImage: MenuBarIcon.image(
            session: model.sessionFraction,
            weekly: model.weeklyFraction,
            sessionPace: sessionPace,
            weeklyPace: weeklyPace,
            text: text,
            style: style
        ))
        .accessibilityLabel(accessibilityText)
    }
}
