import Foundation
import Testing
@testable import LastCallKit

@Suite struct CodexTests {
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let observed = "2026-11-18T10:00:00Z"

    // MARK: Fixtures

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "codex-tests-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func folder(in home: URL, daysAgo: Int = 0) throws -> URL {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let url = home.appending(path: "sessions/\(String(format: "%04d/%02d/%02d", parts.year!, parts.month!, parts.day!))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ lines: [String], named name: String, in folder: URL, modified: Date) throws -> URL {
        let url = folder.appending(path: name)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func window(_ used: Double, minutes: Int, resetsAt: Int? = nil, resetsIn: Int? = nil) -> String {
        var fields = ["\"used_percent\": \(used)", "\"window_minutes\": \(minutes)"]
        if let resetsAt { fields.append("\"resets_at\": \(resetsAt)") }
        if let resetsIn { fields.append("\"resets_in_seconds\": \(resetsIn)") }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    private func tokenCount(
        timestamp: String? = nil,
        limitID: String? = "codex",
        primary: String? = nil,
        secondary: String? = nil,
        plan: String? = "plus"
    ) -> String {
        var limits: [String] = []
        if let limitID { limits.append("\"limit_id\": \"\(limitID)\"") }
        limits.append("\"primary\": \(primary ?? "null")")
        limits.append("\"secondary\": \(secondary ?? "null")")
        if let plan { limits.append("\"plan_type\": \"\(plan)\"") }
        return """
        {"timestamp": "\(timestamp ?? observed)", "type": "event_msg", "payload": {"type": "token_count", "info": null, "rate_limits": {\(limits.joined(separator: ", "))}}}
        """
    }

    private var future5h: Int { Int(now.timeIntervalSince1970) + 2 * 3600 }
    private var futureWeek: Int { Int(now.timeIntervalSince1970) + 3 * 86400 }

    private func reader(_ home: URL) -> CodexUsageReader {
        let fixed = now
        return CodexUsageReader(home: home, now: { fixed })
    }

    // MARK: Tests

    @Test func readsBothWindowsAndPlan() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            [tokenCount(primary: window(10, minutes: 300, resetsAt: future5h), secondary: window(2, minutes: 10080, resetsAt: futureWeek))],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.plan == "plus")
        #expect(reading.snapshot.fiveHour == UsageWindow(utilization: 10, resetsAt: Date(timeIntervalSince1970: Double(future5h))))
        #expect(reading.snapshot.sevenDay == UsageWindow(utilization: 2, resetsAt: Date(timeIntervalSince1970: Double(futureWeek))))
        #expect(reading.snapshot.fetchedAt == ISODate.parse(observed))
    }

    @Test func picksNewestFile() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let day = try folder(in: home)
        try write([tokenCount(primary: window(11, minutes: 300, resetsAt: future5h))],
                  named: "rollout-old.jsonl", in: day, modified: now.addingTimeInterval(-600))
        try write([tokenCount(primary: window(55, minutes: 300, resetsAt: future5h))],
                  named: "rollout-new.jsonl", in: day, modified: now)
        let older = try folder(in: home, daysAgo: 2)
        try write([tokenCount(primary: window(77, minutes: 300, resetsAt: future5h))],
                  named: "rollout-older.jsonl", in: older, modified: now.addingTimeInterval(-86400))
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour?.utilization == 55)
    }

    @Test func lastRecordInAFileWins() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            [
                tokenCount(timestamp: "2026-11-18T09:00:00Z", primary: window(5, minutes: 300, resetsAt: future5h)),
                tokenCount(timestamp: "2026-11-18T09:30:00Z", primary: window(8, minutes: 300, resetsAt: future5h)),
                #"{"timestamp": "2026-11-18T09:31:00Z", "type": "event_msg", "payload": {"type": "agent_message"}}"#
            ],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour?.utilization == 8)
        #expect(reading.snapshot.fetchedAt == ISODate.parse("2026-11-18T09:30:00Z"))
    }

    @Test func skipsNullRateLimits() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let nullLimits = #"{"timestamp": "2026-11-18T10:05:00Z", "type": "event_msg", "payload": {"type": "token_count", "rate_limits": null}}"#
        try write(
            [
                tokenCount(timestamp: "2026-11-18T09:00:00Z", primary: window(21, minutes: 300, resetsAt: future5h)),
                nullLimits,
                tokenCount(timestamp: "2026-11-18T10:06:00Z", primary: nil, secondary: nil)
            ],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour?.utilization == 21)
    }

    @Test func fallsBackToAnEarlierFileWhenTheNewestHasNoLimits() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let day = try folder(in: home)
        try write([tokenCount(primary: window(33, minutes: 300, resetsAt: future5h))],
                  named: "rollout-a.jsonl", in: day, modified: now.addingTimeInterval(-3600))
        try write([#"{"timestamp": "2026-11-18T10:00:00Z", "type": "session_meta", "payload": {}}"#],
                  named: "rollout-b.jsonl", in: day, modified: now)
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour?.utilization == 33)
    }

    @Test func mapsWindowsByMinutesNotPosition() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            [tokenCount(primary: window(40, minutes: 10080, resetsAt: futureWeek), secondary: window(6, minutes: 300, resetsAt: future5h))],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour?.utilization == 6)
        #expect(reading.snapshot.sevenDay?.utilization == 40)
    }

    @Test func ignoresUnknownWindowLengths() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            [tokenCount(primary: window(40, minutes: 60, resetsAt: future5h), secondary: window(6, minutes: 10080, resetsAt: futureWeek))],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour == nil)
        #expect(reading.snapshot.sevenDay?.utilization == 6)
    }

    @Test func pastResetBecomesZeroWithNoReset() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let past = Int(now.timeIntervalSince1970) - 60
        try write(
            [tokenCount(primary: window(90, minutes: 300, resetsAt: past), secondary: window(12, minutes: 10080, resetsAt: futureWeek))],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour == UsageWindow(utilization: 0, resetsAt: nil))
        #expect(reading.snapshot.sevenDay?.utilization == 12)
    }

    @Test func readsResetsInSecondsRelativeToTheTimestamp() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // Observed 2026-11-18T10:00:00Z; resets 3 hours later.
        let observedDate = try #require(ISODate.parse(observed))
        try write(
            [tokenCount(primary: window(30, minutes: 300, resetsIn: 3 * 3600))],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let current = observedDate.addingTimeInterval(3600)
        let reading = try #require(try await CodexUsageReader(home: home, now: { current }).read())
        #expect(reading.snapshot.fiveHour?.resetsAt == observedDate.addingTimeInterval(3 * 3600))
        #expect(reading.snapshot.fiveHour?.utilization == 30)
    }

    @Test func resetsInSecondsAlreadyElapsedBecomesZero() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let observedDate = try #require(ISODate.parse(observed))
        try write(
            [tokenCount(primary: window(30, minutes: 300, resetsIn: 600))],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let current = observedDate.addingTimeInterval(3600)
        let reading = try #require(try await CodexUsageReader(home: home, now: { current }).read())
        #expect(reading.snapshot.fiveHour == UsageWindow(utilization: 0, resetsAt: nil))
    }

    @Test func ignoresOtherLimitIDs() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            [
                tokenCount(timestamp: "2026-11-18T09:00:00Z", primary: window(15, minutes: 300, resetsAt: future5h)),
                tokenCount(timestamp: "2026-11-18T09:30:00Z", limitID: "codex_other", primary: window(99, minutes: 300, resetsAt: future5h))
            ],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour?.utilization == 15)
    }

    @Test func acceptsRecordsWithoutALimitID() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            [tokenCount(limitID: nil, primary: window(15, minutes: 300, resetsAt: future5h), plan: nil)],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour?.utilization == 15)
        #expect(reading.plan == nil)
    }

    @Test func missingSessionsFolderReturnsNil() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(try await reader(home).read() == nil)
        let absent = home.appending(path: "nope", directoryHint: .isDirectory)
        #expect(try await reader(absent).read() == nil)
    }

    @Test func ignoresFilesOlderThanEightDays() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write([tokenCount(primary: window(15, minutes: 300, resetsAt: future5h))],
                  named: "rollout-a.jsonl", in: try folder(in: home, daysAgo: 8), modified: now)
        #expect(try await reader(home).read() == nil)
        try write([tokenCount(primary: window(16, minutes: 300, resetsAt: future5h))],
                  named: "rollout-b.jsonl", in: try folder(in: home, daysAgo: 7), modified: now)
        #expect(try await reader(home).read()?.snapshot.fiveHour?.utilization == 16)
    }

    @Test func hugeEarlierLineDoesNotBreakTheTailRead() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let huge = #"{"timestamp": "2026-11-18T08:00:00Z", "type": "response_item", "payload": {"text": ""#
            + String(repeating: "x", count: 3_000_000) + #""}}"#
        try write(
            [huge, tokenCount(primary: window(44, minutes: 300, resetsAt: future5h))],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        let reading = try #require(try await reader(home).read())
        #expect(reading.snapshot.fiveHour?.utilization == 44)
    }

    @Test func recordsOlderThanTheTailAreNotRead() async throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let huge = #"{"timestamp": "2026-11-18T08:00:00Z", "type": "response_item", "payload": {"text": ""#
            + String(repeating: "x", count: 2_000_000) + #""}}"#
        try write(
            [tokenCount(primary: window(44, minutes: 300, resetsAt: future5h)), huge],
            named: "rollout-a.jsonl", in: try folder(in: home), modified: now
        )
        #expect(try await reader(home).read() == nil)
    }
}
