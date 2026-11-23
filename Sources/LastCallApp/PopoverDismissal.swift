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
        if window.isKeyWindow { startMonitoringClicks() }
    }

    private func keyWindowChanged(_ keyWindow: NSWindow?) {
        guard let window, let keyWindow else { return }
        if keyWindow === window {
            startMonitoringClicks()
        } else {
            // Another Last Call window took key: the other menu bar popover, Settings or About.
            close()
        }
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
        // orderOut, not close: closing the last window makes SwiftUI quit the app.
        window.orderOut(nil)
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
