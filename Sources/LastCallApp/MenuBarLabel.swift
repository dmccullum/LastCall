import LastCallKit
import SwiftUI

struct MenuBarLabel: View {
    let model: UsageModel
    @AppStorage(SettingsKey.menuBarDisplay) private var display: MenuBarDisplay = .session

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
        // One image holding the capsules and the text, so the item gets the same
        // end padding as the icon-only items beside it.
        Image(nsImage: MenuBarIcon.image(session: model.sessionFraction, weekly: model.weeklyFraction, text: text))
            .accessibilityLabel(accessibilityText)
    }
}
