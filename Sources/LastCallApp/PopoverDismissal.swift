import AppKit
import SwiftUI

extension View {
    /// Closes the popover window when the person clicks anywhere outside Last Call,
    /// including another menu bar item, or opens Last Call's other menu bar item.
    /// MenuBarExtra only closes its window when it resigns key, and clicking a menu bar
    /// item that belongs to another process doesn't take key away from it.
    func dismissesOnOutsideClick() -> some View {
        background(PopoverDismissal())
    }
}

private struct PopoverDismissal: NSViewRepresentable {
    func makeNSView(context: Context) -> DismissalView { DismissalView() }
    func updateNSView(_ nsView: DismissalView, context: Context) {}
}

private final class DismissalView: NSView {
    private var clickMonitor: Any?
    private var observers: [any NSObjectProtocol] = []
    /// The menu bar button that opens this popover. Closing through its action, not by
    /// ordering the window out, keeps MenuBarExtra's open state and the button's
    /// highlight in step with the window.
    private weak var statusButton: NSStatusBarButton?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopWatching()
        guard let window else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                let keyWindow = note.object as? NSWindow
                MainActor.assumeIsolated { self?.keyWindowChanged(keyWindow) }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopMonitoringClicks() }
            }
        ]
        if window.isKeyWindow { becameKey() }
    }

    private func keyWindowChanged(_ keyWindow: NSWindow?) {
        guard let window, let keyWindow else { return }
        if keyWindow === window {
            becameKey()
        } else {
            // Another Last Call window took key: the other menu bar popover, Settings or About.
            close()
        }
    }

    private func becameKey() {
        if statusButton == nil { statusButton = findStatusButton() }
        startMonitoringClicks()
    }

    /// The button being clicked is highlighted while its popover opens. Otherwise, the
    /// popover opens with its left edge at its button's.
    private func findStatusButton() -> NSStatusBarButton? {
        guard let window else { return nil }
        let buttons = NSApp.windows.compactMap { $0.contentView.flatMap(Self.statusBarButton(in:)) }
        if let pressed = buttons.first(where: \.isHighlighted) { return pressed }
        return buttons.min {
            abs(($0.window?.frame.minX ?? .infinity) - window.frame.minX) < abs(($1.window?.frame.minX ?? .infinity) - window.frame.minX)
        }
    }

    private static func statusBarButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusBarButton(in: subview) { return button }
        }
        return nil
    }

    private func startMonitoringClicks() {
        guard clickMonitor == nil else { return }
        // Global monitors see only events sent to other processes, so clicks inside Last Call don't count.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopMonitoringClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func close() {
        guard let window, window.isVisible else { return }
        stopMonitoringClicks()
        // The button's state is on while MenuBarExtra counts its popover as open.
        if let button = statusButton, button.state == .on, let action = button.action {
            NSApp.sendAction(action, to: button.target, from: button)
            // Closed while another Last Call window is key, MenuBarExtra hides the popover
            // but leaves its button on, which draws the item selected.
            if !window.isVisible { button.state = .off }
        } else {
            window.orderOut(nil)
        }
    }

    private func stopWatching() {
        stopMonitoringClicks()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    isolated deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
