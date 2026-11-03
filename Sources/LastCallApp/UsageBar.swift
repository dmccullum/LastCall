import SwiftUI

/// A progress bar with a fill, and a thin tick at how far through its window we are.
struct UsageBar: View {
    let title: String
    let utilization: Double
    /// 0 to 1, or nil to hide the tick.
    let elapsed: Double?
    var height: CGFloat = 8

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { min(max(utilization / 100, 0), 1) }

    static func fillColor(for utilization: Double) -> Color {
        if utilization >= 95 { return .red }
        if utilization >= 80 { return .orange }
        return .accentColor
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
                if contrast == .increased {
                    Capsule().strokeBorder(.secondary, lineWidth: 1)
                }
                Capsule()
                    .fill(Self.fillColor(for: utilization))
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
                    .animation(reduceMotion ? nil : .smooth, value: fraction)
                if let elapsed {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: contrast == .increased ? 2 : 1.5, height: height + 6)
                        .offset(x: min(max(proxy.size.width * elapsed - 0.75, 0), proxy.size.width - 1.5))
                        .opacity(contrast == .increased ? 1 : 0.7)
                }
            }
            .frame(height: height + 6)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height + 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(min(max(utilization, 0), 100).rounded())) percent used")
    }
}
