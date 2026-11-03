import LastCallKit
import SwiftUI

struct MenuBarLabel: View {
    let model: UsageModel
    @AppStorage(SettingsKey.menuBarStyle) private var style: MenuBarStyle = .capsules
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
        switch (session, weekly) {
        case let (session?, weekly?): "Claude session \(session) percent, weekly \(weekly) percent"
        case let (session?, nil): "Claude session \(session) percent"
        case let (nil, weekly?): "Claude weekly \(weekly) percent"
        default: model.problem == .signedOut ? "Claude usage, signed out" : "Claude usage"
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
