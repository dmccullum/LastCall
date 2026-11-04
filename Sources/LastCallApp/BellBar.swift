import AppKit
import LastCallKit
import SwiftUI

/// A usage track with draggable notification bells. Click the track to add a bell,
/// drag one to move it, drag it away from the track or press Delete to remove it.
struct BellBar: View {
    /// "Session" or "Weekly"; used for accessibility labels.
    let name: String
    @Binding var thresholds: [Int]
    /// 0 to 100, or nil when there is no data yet.
    let utilization: Double?

    private struct Bell: Identifiable, Equatable {
        let id = UUID()
        var value: Int
    }

    @State private var bells: [Bell] = []
    @State private var dragging: UUID?
    @State private var dragStart = 0
    @State private var pulledAway = false
    @State private var dragDelta = CGSize.zero
    @State private var hovered: UUID?
    @FocusState private var focused: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private let trackHeight: CGFloat = 10
    private let dotSize: CGFloat = 12
    private let trackHitHeight: CGFloat = 24
    /// Below the track center: the dot's radius plus its ring.
    private let dotClearance: CGFloat = 9
    private let inset: CGFloat = 16
    private let pillWidth: CGFloat = 62
    private let pillHeight: CGFloat = 28
    private let margin: CGFloat = 7
    private let shortStem: CGFloat = 11
    private let tallStem: CGFloat = 35
    /// How far the pill can be pulled from where it rests before releasing removes it.
    private let removeDistance: CGFloat = 40
    private let maxBells = AlertSettings.maxThresholds

    private var spring: Animation? { reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2) }
    private var used: Double { min(max(utilization ?? 0, 0), 100) }

    var body: some View {
        lane
        .onAppear { bells = thresholds.map { Bell(value: $0) } }
        .onChange(of: thresholds) { _, new in
            if Set(new) != Set(bells.map(\.value)) { bells = new.map { Bell(value: $0) } }
        }
    }

    /// Room for the pill, stem and dot of the tallest bell; just the track when there are none.
    private func laneHeight(stems: [UUID: CGFloat]) -> CGFloat {
        guard let tallest = stems.values.max() else { return trackHitHeight }
        return margin + pillHeight + tallest + dotClearance
    }

    private var lane: some View {
        let stems = stemLengths()
        let height = laneHeight(stems: stems)
        return GeometryReader { proxy in
            let width = proxy.size.width
            let trackY = height - dotClearance
            let origin = proxy.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                track(width: width)
                    .position(x: width / 2, y: trackY)
                ForEach(bells) { bell in
                    mark(for: bell, width: width, origin: origin, trackY: trackY, stem: stems[bell.id] ?? shortStem)
                        .zIndex(dragging == bell.id ? 10 : 0)
                        .transition(reduceMotion ? .identity : .scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .coordinateSpace(.named("lane"))
        }
        .frame(height: height)
    }

    // MARK: Track

    private func x(for value: Double, width: CGFloat) -> CGFloat {
        inset + (width - inset * 2) * value / 100
    }

    private func track(width: CGFloat) -> some View {
        let trackWidth = width - inset * 2
        return ZStack(alignment: .leading) {
            Capsule().fill(contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
            if used > 0 {
                Capsule()
                    .fill(UsageBar.fillColor(for: used))
                    .frame(width: max(trackHeight, trackWidth * used / 100))
            }
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(.capsule)
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(.secondary, lineWidth: 1)
                    .frame(width: trackWidth, height: trackHeight)
            }
        }
        .frame(width: width, height: trackHitHeight)
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onTapGesture(coordinateSpace: .local) { location in
            let fraction = (location.x - inset) / trackWidth
            add(snapped(fraction * 100))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) usage")
        .accessibilityValue("\(Int(used.rounded())) percent used")
        .accessibilityAction(named: "Add Bell") { addAtNextFreeSlot() }
    }

    // MARK: Bells

    private func mark(for bell: Bell, width: CGFloat, origin: CGPoint, trackY: CGFloat, stem: CGFloat) -> some View {
        let isDragging = dragging == bell.id
        let passed = Double(bell.value) <= used
        let color: Color = passed ? .gray : .accentColor
        let dotX = x(for: Double(bell.value), width: width)
        let pillX = min(max(dotX, pillWidth / 2), width - pillWidth / 2)
        let frameWidth = pillWidth + margin * 2
        let frameHeight = margin + pillHeight + stem + margin
        let dotCenterY = margin + pillHeight + stem
        let ring = Color(nsColor: .controlBackgroundColor)
        let away = isDragging && pulledAway
        let delta = isDragging ? dragDelta : .zero
        let pillDX: CGFloat = 0
        let pillTop = margin + delta.height
        let pillCenterX = frameWidth / 2 + pillDX
        let stemEnd = pillTop + pillHeight / 2 < dotCenterY ? pillTop + pillHeight : pillTop
        let stemFrom = min(stemEnd, dotCenterY)
        let stemLength = max(abs(dotCenterY - stemEnd), 0)

        return ZStack(alignment: .topLeading) {
            if !away {
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: stemLength)
                    .offset(x: frameWidth / 2 + (dotX - pillX) - 1.5, y: stemFrom)
                Circle().fill(ring).frame(width: dotSize + 5, height: dotSize + 5)
                    .offset(x: frameWidth / 2 + (dotX - pillX) - (dotSize + 5) / 2, y: dotCenterY - (dotSize + 5) / 2)
                Circle().fill(color).frame(width: dotSize, height: dotSize)
                    .offset(x: frameWidth / 2 + (dotX - pillX) - dotSize / 2, y: dotCenterY - dotSize / 2)
            }
            // While dragging, the pill is drawn by `FloatingBellPill` so it can leave the row.
            BellPillView(value: bell.value, color: color)
                .opacity(isDragging ? 0 : 1)
                .offset(x: pillCenterX - pillWidth / 2, y: pillTop)
            // Keyboard focus only; the system ring would wrap the stem and dot too.
            if focused == bell.id {
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2.5)
                    .frame(width: pillWidth + 9, height: pillHeight + 9)
                    .offset(x: margin - 4.5, y: margin - 4.5)
            }
            if hovered == bell.id && dragging == nil {
                Button { remove(bell.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary, ring)
                }
                .buttonStyle(.plain)
                .help("Remove Bell")
                .offset(x: margin + pillWidth - 10, y: margin - 4)
            }
        }
        .frame(width: frameWidth, height: frameHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? bell.id : (hovered == bell.id ? nil : hovered) }
        .pointerStyle(isDragging ? .grabActive : .grabIdle)
        .position(x: pillX, y: trackY - dotCenterY + frameHeight / 2)
        .gesture(drag(bell, width: width, origin: origin, trackY: trackY, stem: stem))
        .focusable(interactions: .activate)
        .focusEffectDisabled()
        .focused($focused, equals: bell.id)
        .onMoveCommand { direction in
            switch direction {
            case .left: move(bell.id, by: -5)
            case .right: move(bell.id, by: 5)
            default: break
            }
        }
        .onDeleteCommand { remove(bell.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) bell")
        .accessibilityValue("\(bell.value) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(bell.id, by: 5)
            case .decrement: move(bell.id, by: -5)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Remove Bell") { remove(bell.id) }
    }

    /// A bell within 20% of the one before it gets the tall stem when that one is short, and vice versa.
    private func stemLengths() -> [UUID: CGFloat] {
        var result: [UUID: CGFloat] = [:]
        var previous: (value: Int, tall: Bool)?
        for bell in bells.sorted(by: { $0.value < $1.value }) {
            let tall = previous.map { bell.value - $0.value < 20 ? !$0.tall : false } ?? false
            result[bell.id] = tall ? tallStem : shortStem
            previous = (bell.value, tall)
        }
        return result
    }

    private func drag(_ bell: Bell, width: CGFloat, origin: CGPoint, trackY: CGFloat, stem: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                guard let index = bells.firstIndex(where: { $0.id == bell.id }) else { return }
                if dragging != bell.id {
                    dragging = bell.id
                    dragStart = bells[index].value
                }
                let perPercent = (width - inset * 2) / 100
                bells[index].value = snapped(Double(dragStart) + value.translation.width / perPercent)
                dragDelta = value.translation
                pulledAway = abs(value.translation.height) > removeDistance
                // Within range the pill stays over its snapped dot; past it, it follows the pointer.
                let dotX = x(for: Double(bells[index].value), width: width)
                let restX = min(max(dotX, pillWidth / 2), width - pillWidth / 2)
                let centerX = pulledAway ? x(for: Double(dragStart), width: width) + value.translation.width : restX
                let restY = trackY - stem - pillHeight / 2
                BellDrag.shared.pill = FloatingPill(
                    value: bells[index].value,
                    color: Double(bells[index].value) <= used ? .gray : .accentColor,
                    center: CGPoint(x: origin.x + centerX, y: origin.y + restY + value.translation.height),
                    dimmed: pulledAway,
                    vanishing: false
                )
                // SwiftUI pointer styles can't express the Dock's poof cursor.
                (pulledAway ? NSCursor.disappearingItem : NSCursor.closedHand).set()
            }
            .onEnded { _ in
                let id = bell.id
                if pulledAway {
                    let pointer = NSEvent.mouseLocation
                    NSAnimationEffect.disappearingItemDefault.show(centeredAt: pointer, size: .zero)
                    NSCursor.arrow.set()
                    // The row drops the bell at once; only the floating copy plays out the exit.
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) {
                        bells.removeAll { $0.id == id }
                        hovered = nil
                        publish()
                    }
                    guard !reduceMotion else { finishDrag(); return }
                    withAnimation(.easeIn(duration: 0.15)) { BellDrag.shared.pill?.vanishing = true }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        finishDrag()
                    }
                } else {
                    withAnimation(spring) { finishDrag() }
                    commit(merging: id)
                }
            }
    }

    private func finishDrag() {
        BellDrag.shared.pill = nil
        dragging = nil
        pulledAway = false
        dragDelta = .zero
    }

    // MARK: Editing

    private func snapped(_ percent: Double) -> Int {
        min(max(Int((percent / 5).rounded()) * 5, 5), 100)
    }

    private func add(_ value: Int) {
        guard bells.count < maxBells, !bells.contains(where: { $0.value == value }) else { return }
        withAnimation(spring) {
            bells.append(Bell(value: value))
            publish()
        }
    }

    private func addAtNextFreeSlot() {
        let start = (Int(used / 5) + 1) * 5
        guard start <= 100 else { return }
        if let value = stride(from: start, through: 100, by: 5).first(where: { v in !bells.contains { $0.value == v } }) {
            add(value)
        }
    }

    private func remove(_ id: UUID) {
        withAnimation(spring) {
            bells.removeAll { $0.id == id }
            hovered = nil
            publish()
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let index = bells.firstIndex(where: { $0.id == id }) else { return }
        // Skips over occupied slots so two bells never merge from the keyboard.
        var value = bells[index].value + delta
        while (5...100).contains(value), bells.contains(where: { $0.value == value }) { value += delta }
        guard (5...100).contains(value) else { return }
        withAnimation(spring) {
            bells[index].value = value
            publish()
        }
    }

    /// Ends a drag: drops the dragged bell if another sits at the same percentage.
    private func commit(merging id: UUID) {
        withAnimation(spring) {
            if let index = bells.firstIndex(where: { $0.id == id }),
               bells.contains(where: { $0.id != id && $0.value == bells[index].value }) {
                bells.remove(at: index)
            }
            publish()
        }
    }

    private func publish() {
        thresholds = bells.map(\.value).sorted()
    }
}

/// The bell pill: icon and percentage on the accent (or gray) capsule.
struct BellPillView: View {
    let value: Int
    let color: Color

    static let width: CGFloat = 62
    static let height: CGFloat = 28

    var body: some View {
        ZStack(alignment: .top) {
            Capsule().fill(color.mix(with: .black, by: 0.25))
                .frame(height: Self.height)
            Capsule().fill(color)
                .frame(height: Self.height - 2)
            HStack(spacing: 3) {
                Image(systemName: "bell.fill")
                Text("\(value)%").monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: Self.height - 2)
        }
        .frame(width: Self.width, height: Self.height)
    }
}

struct FloatingPill: Equatable {
    var value: Int
    var color: Color
    /// Window coordinates.
    var center: CGPoint
    var dimmed: Bool
    var vanishing: Bool
}

/// The pill being dragged. Shown by `FloatingBellPill` above the whole Form, because a Form row clips its contents.
@Observable
final class BellDrag {
    static let shared = BellDrag()
    var pill: FloatingPill?
}

/// Draws the dragged pill over the Settings content, outside any row.
struct FloatingBellPill: View {
    private let drag = BellDrag.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let pill = drag.pill {
                let frame = proxy.frame(in: .global)
                BellPillView(value: pill.value, color: pill.color)
                    .scaleEffect(pill.vanishing && !reduceMotion ? 0.3 : 1.08)
                    .opacity(pill.vanishing ? 0 : (pill.dimmed ? 0.6 : 1))
                    .position(x: pill.center.x - frame.minX, y: pill.center.y - frame.minY)
            }
        }
        .allowsHitTesting(false)
    }
}
