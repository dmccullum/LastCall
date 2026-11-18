import AppKit
import Foundation
import LastCallKit
import Observation

/// One per service: `UsageModel.claude` polls the usage endpoint, `UsageModel.codex`
/// reads Codex’s session logs.
@Observable
final class UsageModel {
    static let claude = UsageModel(service: .claude)
    static let codex = UsageModel(service: .codex)

    static func model(for service: Service) -> UsageModel {
        switch service {
        case .claude: claude
        case .codex: codex
        }
    }

    let service: Service

    private init(service: Service) {
        self.service = service
    }

    enum Problem: Equatable {
        case signedOut
        case message(String)
    }

    private(set) var snapshot: UsageSnapshot?
    private(set) var lastUpdated: Date?
    private(set) var problem: Problem?
    private(set) var isRefreshing = false
    /// API-list-price cost of Claude Code transcripts in the current windows. Nil until the first scan.
    private(set) var sessionCost: CostEstimate?
    private(set) var weeklyCost: CostEstimate?
    /// The `plan_type` Codex recorded, e.g. “plus”. Codex only.
    private(set) var plan: String?

    @ObservationIgnored private lazy var usageService = UsageService()
    @ObservationIgnored private lazy var scanner = TranscriptScanner()
    @ObservationIgnored private let codexReader = CodexUsageReader()
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var interval: TimeInterval = UsageModel.baseInterval
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var settingsObserver: (any NSObjectProtocol)?

    static let baseInterval: TimeInterval = 300
    static let signedOutInterval: TimeInterval = 60
    static let maxInterval: TimeInterval = 1800
    static let codexInterval: TimeInterval = 60

    /// “Plus plan”, from the plan type Codex recorded.
    var planText: String? { plan.map { "\($0.capitalized) plan" } }

    var sessionFraction: Double? { snapshot?.fiveHour.map { min(max($0.utilization / 100, 0), 1) } }
    var weeklyFraction: Double? { snapshot?.sevenDay.map { min(max($0.utilization / 100, 0), 1) } }

    /// Starts or stops polling whenever this service’s toggle in Settings changes.
    func followSettings() {
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncWithSettings() }
        }
        syncWithSettings()
    }

    private func syncWithSettings() {
        if ServiceSettings(service).isEnabled() { start() } else { stop() }
    }

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

    /// Stops polling and the wake observer. `start()` resumes.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
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
        if service == .codex { return Self.codexInterval }
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
        switch service {
        case .claude: await refreshClaude()
        case .codex: await refreshCodex()
        }
    }

    private func refreshCodex() async {
        do {
            guard let reading = try await codexReader.read() else {
                // “No data”: Codex has recorded no limits in the last 8 days.
                snapshot = nil
                plan = nil
                lastUpdated = nil
                problem = .signedOut
                return
            }
            let previous = snapshot
            snapshot = reading.snapshot
            plan = reading.plan
            lastUpdated = reading.snapshot.fetchedAt
            problem = nil
            AlertCenter.shared.evaluate(service: .codex, previous: previous, current: reading.snapshot)
        } catch {
            problem = .message("Couldn’t read Codex’s session logs. Last Call will retry in 1 minute.")
        }
    }

    private func refreshClaude() async {
        do {
            let fresh = try await usageService.fetchUsage()
            let previous = snapshot
            snapshot = fresh
            lastUpdated = fresh.fetchedAt
            problem = nil
            interval = Self.baseInterval
            AlertCenter.shared.evaluate(service: .claude, previous: previous, current: fresh)
            // Separate task: a slow scan must not delay the next poll.
            Task { await self.scanCosts() }
        } catch let error as UsageError {
            handle(error)
        } catch {
            handle(.network)
        }
    }

    /// Totals Claude Code transcript cost for the current windows. Does nothing while the
    /// setting is off, so no transcript is read and no cache file is written.
    func scanCosts() async {
        guard service == .claude, UserDefaults.standard.bool(forKey: SettingsKey.showAPIEquivalent) else { return }
        guard !isScanning, let snapshot else { return }
        isScanning = true
        defer { isScanning = false }
        let session = snapshot.fiveHour?.resetsAt.map { $0.addingTimeInterval(-5 * 3600)..<$0 }
        let week = snapshot.sevenDay?.resetsAt.map { $0.addingTimeInterval(-7 * 86400)..<$0 }
        let windows = [session, week].compactMap { $0 }
        let totals = await scanner.scan(windows: windows)
        var next = totals.makeIterator()
        sessionCost = session == nil ? nil : next.next().map(CostEstimate.init)
        weeklyCost = week == nil ? nil : next.next().map(CostEstimate.init)
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
        await refreshIfStale(after: service == .codex ? 10 : 60)
        if let snapshot { return UsageFormat.summary(snapshot) }
        if service == .codex {
            return problem == .signedOut ? "No Codex usage found. Send a request in Codex first." : "Codex usage isn’t available right now."
        }
        return problem == .signedOut ? "Sign in to Claude Code to see your limits." : "Claude usage isn’t available right now."
    }
}
