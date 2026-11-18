import Foundation

/// The newest Codex rate-limit record, as the 5-hour and weekly windows.
public struct CodexReading: Equatable, Sendable {
    /// `snapshot.fetchedAt` is the record's timestamp: when Codex observed the limits.
    public var snapshot: UsageSnapshot
    /// The `plan_type` Codex recorded, e.g. “plus”.
    public var plan: String?

    public init(snapshot: UsageSnapshot, plan: String?) {
        self.snapshot = snapshot
        self.plan = plan
    }
}

/// Reads the rate limits Codex writes into its session logs
/// (`sessions/YYYY/MM/DD/rollout-*.jsonl` under the Codex home).
/// Reads only those files: no `auth.json`, no network.
public actor CodexUsageReader {
    /// `$CODEX_HOME` when set and non-empty, else `~/.codex`.
    public static var defaultHome: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    /// Date folders searched: today and the 7 days before it.
    static let daysSearched = 8
    static let maxFiles = 5
    static let tailBytes = 1_048_576

    private static let fiveHourMinutes = 300
    private static let weeklyMinutes = 10080

    private let home: URL
    private let now: @Sendable () -> Date

    public init(home: URL = CodexUsageReader.defaultHome, now: @escaping @Sendable () -> Date = { Date() }) {
        self.home = home
        self.now = now
    }

    /// The newest reading, or nil when Codex has left no rate-limit data in the last 8 days.
    public func read() throws -> CodexReading? {
        let current = now()
        for file in candidateFiles(now: current).prefix(Self.maxFiles) {
            if let reading = try reading(in: file, now: current) { return reading }
        }
        return nil
    }

    // MARK: Files

    private func candidateFiles(now: Date) -> [URL] {
        let fileManager = FileManager.default
        let calendar = Calendar.current
        let sessions = home.appending(path: "sessions", directoryHint: .isDirectory)
        var found: [(url: URL, modified: Date)] = []
        for offset in 0..<Self.daysSearched {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { continue }
            let folder = sessions
                .appending(path: String(format: "%04d", year), directoryHint: .isDirectory)
                .appending(path: String(format: "%02d", month), directoryHint: .isDirectory)
                .appending(path: String(format: "%02d", dayOfMonth), directoryHint: .isDirectory)
            guard let urls = try? fileManager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for url in urls where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                found.append((url, modified ?? .distantPast))
            }
        }
        return found.sorted { $0.modified > $1.modified }.map(\.url)
    }

    // MARK: Reading

    private func reading(in file: URL, now: Date) throws -> CodexReading? {
        let tail = try Self.tail(of: file)
        let marker = Data("\"rate_limits\"".utf8)
        let decoder = JSONDecoder()
        for line in tail.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).reversed() {
            let data = Data(line)
            guard data.range(of: marker) != nil,
                  let record = try? decoder.decode(Record.self, from: data),
                  let limits = record.payload?.rateLimits,
                  limits.primary != nil || limits.secondary != nil
            else { continue }
            if let id = limits.limitID, id != "codex" { continue }
            let observed = record.timestamp.flatMap(ISODate.parse)
                ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? now
            return CodexReading(snapshot: snapshot(limits, observed: observed, now: now), plan: limits.planType)
        }
        return nil
    }

    private func snapshot(_ limits: RateLimits, observed: Date, now: Date) -> UsageSnapshot {
        var snapshot = UsageSnapshot(fetchedAt: observed)
        for raw in [limits.primary, limits.secondary].compactMap({ $0 }) {
            guard let window = window(raw, observed: observed, now: now) else { continue }
            switch raw.windowMinutes.map({ Int($0.rounded()) }) {
            case Self.fiveHourMinutes: snapshot.fiveHour = window
            case Self.weeklyMinutes: snapshot.sevenDay = window
            default: break
            }
        }
        return snapshot
    }

    private func window(_ raw: RawWindow, observed: Date, now: Date) -> UsageWindow? {
        guard let used = raw.usedPercent else { return nil }
        let reset = raw.resetsAt.map { Date(timeIntervalSince1970: $0) }
            ?? raw.resetsInSeconds.map { observed.addingTimeInterval($0) }
        // A window that has reset starts a new one on the next request.
        if let reset, reset <= now { return UsageWindow(utilization: 0, resetsAt: nil) }
        return UsageWindow(utilization: used, resetsAt: reset)
    }

    /// The last `tailBytes` of the file. When that cuts into the middle of a line, the partial line is dropped.
    private static func tail(of file: URL) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
            try handle.seek(toOffset: start)
            var data = try handle.readToEnd() ?? Data()
            if start > 0 {
                guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else { return Data() }
                data = data.subdata(in: data.index(after: newline)..<data.endIndex)
            }
            return data
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return Data()
        } catch {
            throw UsageError.unreadableResponse
        }
    }

    // MARK: Decoding

    private struct Record: Decodable {
        var timestamp: String?
        var payload: Payload?
    }

    private struct Payload: Decodable {
        var rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
    }

    private struct RateLimits: Decodable {
        var limitID: String?
        var primary: RawWindow?
        var secondary: RawWindow?
        var planType: String?

        enum CodingKeys: String, CodingKey {
            case limitID = "limit_id"
            case primary
            case secondary
            case planType = "plan_type"
        }
    }

    private struct RawWindow: Decodable {
        var usedPercent: Double?
        var windowMinutes: Double?
        /// Unix seconds.
        var resetsAt: Double?
        /// Older Codex versions: seconds after the record’s timestamp.
        var resetsInSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
            case resetsInSeconds = "resets_in_seconds"
        }
    }
}
