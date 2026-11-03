import AppKit
import Foundation
import LastCallKit
import Observation

@Observable
final class UsageModel {
    static let shared = UsageModel()

    enum Problem: Equatable {
        case signedOut
        case message(String)
    }

    private(set) var snapshot: UsageSnapshot?
    private(set) var lastUpdated: Date?
    private(set) var problem: Problem?
    private(set) var isRefreshing = false

    @ObservationIgnored private let service = UsageService()
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var interval = UsageModel.baseInterval
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    static let baseInterval: TimeInterval = 300
    static let signedOutInterval: TimeInterval = 60
    static let maxInterval: TimeInterval = 1800

    var sessionFraction: Double? { snapshot?.fiveHour.map { min(max($0.utilization / 100, 0), 1) } }
    var weeklyFraction: Double? { snapshot?.sevenDay.map { min(max($0.utilization / 100, 0), 1) } }

    /// Starts polling and the wake observer. Safe to call more than once.
    func start() {
        guard pollTask == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartPolling(firstDelay: 5) }
        }
        restartPolling(firstDelay: 0)
    }

    private func restartPolling(firstDelay: TimeInterval) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            if firstDelay > 0 { try? await Task.sleep(for: .seconds(firstDelay)) }
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let delay = self.nextDelay()
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func nextDelay() -> TimeInterval {
        let base = problem == .signedOut ? Self.signedOutInterval : interval
        let jitter = problem == .signedOut ? 0 : Double.random(in: -15...15)
        return max(30, base + jitter)
    }

    /// Fetches now unless an attempt was made within `age` seconds.
    func refreshIfStale(after age: TimeInterval = 60) async {
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < age { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastAttempt = Date()
        defer { isRefreshing = false }
        do {
            let fresh = try await service.fetchUsage()
            let previous = snapshot
            snapshot = fresh
            lastUpdated = fresh.fetchedAt
            problem = nil
            interval = Self.baseInterval
            AlertCenter.shared.evaluate(previous: previous, current: fresh)
        } catch let error as UsageError {
            handle(error)
        } catch {
            handle(.network)
        }
    }

    private func handle(_ error: UsageError) {
        switch error {
        case .signedOut, .unauthorized:
            problem = .signedOut
            return
        case .rateLimited(let retryAfter):
            interval = min(max(interval * 2, retryAfter ?? 0), Self.maxInterval)
            problem = .message("Claude is limiting requests. Last Call will retry in \(retryText).")
        case .network:
            problem = .message("Couldn’t reach Claude. Last Call will retry in \(retryText).")
        case .server(let status):
            problem = .message("Claude returned an error (\(status)). Last Call will retry in \(retryText).")
        case .unreadableResponse:
            problem = .message("Couldn’t read Claude’s response. Last Call will retry in \(retryText).")
        case .keychain:
            problem = .message("Couldn’t read Claude Code’s sign-in. Last Call will retry in \(retryText).")
        }
    }

    private var retryText: String {
        let minutes = Int((interval / 60).rounded())
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// The sentence the App Intent returns.
    func summaryText() async -> String {
        await refreshIfStale(after: 60)
        if let snapshot { return UsageFormat.summary(snapshot) }
        return problem == .signedOut ? "Sign in to Claude Code to see your limits." : "Claude usage isn’t available right now."
    }
}
