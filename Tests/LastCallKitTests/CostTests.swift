import Foundation
import Testing
@testable import LastCallKit

private func usage(
    id: String = "msg_1", model: String = "claude-opus-4-8", at time: TimeInterval = 1_000_000,
    input: Int = 0, w5: Int = 0, w1: Int = 0, read: Int = 0, output: Int = 0,
    fast: Bool = false, us: Bool = false
) -> TranscriptUsage {
    TranscriptUsage(
        messageID: id, model: model, timestamp: Date(timeIntervalSince1970: time),
        tokens: TokenCounts(input: input, cacheWrite5m: w5, cacheWrite1h: w1, cacheRead: read, output: output),
        fast: fast, usGeo: us
    )
}

private func close(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-9
}

@Suite struct PricingTests {
    @Test func standardCost() {
        // Opus 4.8: 5 / 6.25 / 10 / 0.50 / 25 per million.
        let u = usage(input: 1_000_000, w5: 1_000_000, w1: 1_000_000, read: 1_000_000, output: 1_000_000)
        #expect(close(APIPricing.cost(of: u), 5 + 6.25 + 10 + 0.5 + 25))
    }

    @Test func oneHourWritesCostMoreThanFiveMinute() {
        #expect(close(APIPricing.cost(of: usage(w5: 1_000_000)), 6.25))
        #expect(close(APIPricing.cost(of: usage(w1: 1_000_000)), 10))
    }

    @Test func fastModeUsesFastRates() {
        let u = usage(model: "claude-opus-4-8", input: 1_000_000, w5: 1_000_000, w1: 1_000_000, read: 1_000_000, output: 1_000_000, fast: true)
        #expect(close(APIPricing.cost(of: u), 10 + 12.5 + 20 + 1 + 50))
        let five = usage(model: "claude-opus-5-5", input: 1_000_000, read: 1_000_000, output: 1_000_000, fast: true)
        #expect(close(APIPricing.cost(of: five), 8 + 0.4 + 40))
    }

    @Test func fastFlagIsIgnoredWithoutFastRates() {
        let u = usage(model: "claude-sonnet-4-6", input: 1_000_000, fast: true)
        #expect(close(APIPricing.cost(of: u), 3))
    }

    @Test func usGeoMultipliesEveryCategoryForNewModels() {
        let u = usage(model: "claude-opus-4-8", input: 1_000_000, output: 1_000_000, us: true)
        #expect(close(APIPricing.cost(of: u), (5 + 25) * 1.1))
        let old = usage(model: "claude-opus-4-5", input: 1_000_000, output: 1_000_000, us: true)
        #expect(close(APIPricing.cost(of: old), 5 + 25))
    }

    @Test func haiku55BelowAndAboveHundredThousand() {
        let small = usage(model: "claude-haiku-5-5", input: 50_000, read: 50_000, output: 1_000_000)
        #expect(close(APIPricing.cost(of: small), (50_000 * 0.10 + 50_000 * 0.01) / 1e6 + 0.50))
        let big = usage(model: "claude-haiku-5-5", input: 50_000, read: 50_001, output: 1_000_000)
        #expect(close(APIPricing.cost(of: big), (50_000 * 0.50 + 50_001 * 0.05) / 1e6 + 2.50))
    }

    @Test func modelPrefixMatching() {
        #expect(APIPricing.price(for: "claude-opus-4-8")?.prefix == "claude-opus-4-8")
        #expect(APIPricing.price(for: "claude-opus-4-8[1m]")?.prefix == "claude-opus-4-8")
        #expect(APIPricing.price(for: "claude-opus-4-20250514")?.prefix == "claude-opus-4")
        #expect(APIPricing.price(for: "claude-opus-4-1-20250805")?.prefix == "claude-opus-4-1")
        #expect(APIPricing.price(for: "claude-3-5-haiku-20241022")?.prefix == "claude-3-5-haiku")
        #expect(APIPricing.price(for: "claude-sonnet-5-5")?.prefix == "claude-sonnet-5-5")
        #expect(APIPricing.price(for: "claude-sonnet-5")?.prefix == "claude-sonnet-5")
        #expect(APIPricing.price(for: "claude-fable-5-1")?.prefix == "claude-fable-5-1")
    }

    @Test func unknownModelsHaveNoPrice() {
        #expect(APIPricing.price(for: "claude-opus-4-10") == nil)
        #expect(APIPricing.price(for: "gpt-5") == nil)
        #expect(APIPricing.price(for: "<synthetic>") == nil)
        #expect(APIPricing.cost(of: usage(model: "mystery-1", input: 5)) == nil)
    }
}

@Suite struct ParsingTests {
    let line = """
    {"type":"assistant","timestamp":"2026-11-03T12:19:57.199Z","requestId":"req_1","extra":[1,2],"message":{"id":"msg_A","model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_creation_input_tokens":93538,"cache_read_input_tokens":7,"output_tokens":586,"cache_creation":{"ephemeral_1h_input_tokens":93000,"ephemeral_5m_input_tokens":538},"speed":"fast","inference_geo":"us"}}}
    """

    @Test func decodesAllFields() throws {
        let u = try #require(TranscriptUsage.parse(line: line))
        #expect(u.messageID == "msg_A")
        #expect(u.model == "claude-opus-5-5")
        #expect(u.tokens == TokenCounts(input: 2, cacheWrite5m: 538, cacheWrite1h: 93000, cacheRead: 7, output: 586))
        #expect(u.fast && u.usGeo)
        #expect(abs(u.timestamp.timeIntervalSince1970 - 1_793_708_397.199) < 0.001)
    }

    @Test func missingCacheCreationSplitCountsAsFiveMinute() throws {
        let l = #"{"timestamp":"2026-11-03T12:19:57Z","message":{"id":"m","model":"claude-opus-4-8","usage":{"cache_creation_input_tokens":40,"output_tokens":1}}}"#
        let u = try #require(TranscriptUsage.parse(line: l))
        #expect(u.tokens.cacheWrite5m == 40 && u.tokens.cacheWrite1h == 0)
        #expect(!u.fast && !u.usGeo)
    }

    @Test func skipsSyntheticAndUsageLessLines() {
        #expect(TranscriptUsage.parse(line: #"{"timestamp":"2026-11-03T12:19:57Z","message":{"id":"m","model":"<synthetic>","usage":{"output_tokens":1}}}"#) == nil)
        #expect(TranscriptUsage.parse(line: #"{"timestamp":"2026-11-03T12:19:57Z","message":{"id":"m","model":"x"}}"#) == nil)
        #expect(TranscriptUsage.parse(line: "not json") == nil)
        #expect(TranscriptUsage.parse(line: "") == nil)
    }

    @Test func captionFormatting() {
        #expect(CostEstimate(dollars: 18.4, hasUnpriced: false).caption == "≈ $18.40 API equivalent")
        #expect(CostEstimate(dollars: 0.042, hasUnpriced: false).caption == "≈ $0.04 API equivalent")
        #expect(CostEstimate(dollars: 1234.5, hasUnpriced: true).caption == "≈ $1,234.50 API equivalent · partial")
    }
}

@Suite struct LedgerTests {
    @Test func dedupeKeepsMaxOutputAndEarliestTimestamp() {
        var ledger = CostLedger()
        ledger.insert(usage(id: "a", at: 200, output: 10))
        ledger.insert(usage(id: "a", at: 100, output: 500))
        ledger.insert(usage(id: "a", at: 300, output: 50))
        #expect(ledger.count == 1)
        #expect(ledger.entries["a"]?.tokens.output == 500)
        #expect(ledger.entries["a"]?.timestamp == Date(timeIntervalSince1970: 100))
    }

    @Test func windowIsHalfOpen() {
        var ledger = CostLedger()
        ledger.insert(usage(id: "before", at: 99, output: 1))
        ledger.insert(usage(id: "start", at: 100, output: 2))
        ledger.insert(usage(id: "inside", at: 150, output: 4))
        ledger.insert(usage(id: "end", at: 200, output: 8))
        let totals = ledger.totals(from: Date(timeIntervalSince1970: 100), to: Date(timeIntervalSince1970: 200))
        #expect(totals.entryCount == 2)
        #expect(totals.tokens.output == 6)
    }

    @Test func unpricedTokensAreReportedNotPriced() {
        var ledger = CostLedger()
        ledger.insert(usage(id: "a", at: 1, input: 1_000_000))
        ledger.insert(usage(id: "b", model: "mystery", at: 1, input: 7, output: 3))
        let totals = ledger.totals(from: .distantPast, to: .distantFuture)
        #expect(close(totals.dollars, 5))
        #expect(totals.unpricedTokens == 10)
        #expect(totals.hasUnpriced)
    }

    @Test func pruneDropsOldEntries() {
        var ledger = CostLedger()
        ledger.insert(usage(id: "old", at: 10))
        ledger.insert(usage(id: "new", at: 20))
        ledger.prune(before: Date(timeIntervalSince1970: 15))
        #expect(ledger.entries.keys.sorted() == ["new"])
    }
}

@Suite struct ScannerTests {
    let now = Date()

    func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lastcall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func stamp(_ offset: TimeInterval) -> String {
        Date(timeIntervalSince1970: now.timeIntervalSince1970 + offset).formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    func line(_ id: String, offset: TimeInterval = -3600, output: Int = 100, model: String = "claude-opus-4-8") -> String {
        #"{"timestamp":"\#(stamp(offset))","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":1,"output_tokens":\#(output)}}}"# + "\n"
    }

    func append(_ text: String, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    func tokens(_ ledger: CostLedger) -> TokenCounts {
        ledger.totals(from: .distantPast, to: .distantFuture).tokens
    }

    @Test func readsNestedFilesAndDedupesAcrossThem() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nested = dir.appending(path: "proj/session/subagents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try append(line("a", output: 10) + line("b", output: 20), to: dir.appending(path: "proj/one.jsonl"))
        try append(line("a", output: 99) + line("c", output: 30), to: nested.appending(path: "two.jsonl"))
        try append("ignored\n", to: dir.appending(path: "proj/notes.txt"))
        let ledger = await TranscriptScanner(root: dir, cacheFile: nil).scan(now: now)
        #expect(ledger.count == 3)
        #expect(ledger.entries["a"]?.tokens.output == 99)
        #expect(tokens(ledger).output == 99 + 20 + 30)
    }

    @Test func incrementalScanReadsOnlyAppendedBytesAndCompletesPartialLines() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "s.jsonl")
        let scanner = TranscriptScanner(root: dir, cacheFile: nil)
        let second = line("b", output: 20)
        let split = second.index(second.startIndex, offsetBy: 40)

        try append(line("a", output: 10) + String(second[..<split]), to: file)
        var ledger = await scanner.scan(now: now)
        #expect(ledger.count == 1)

        try append(String(second[split...]) + line("c", output: 30), to: file)
        ledger = await scanner.scan(now: now)
        #expect(ledger.count == 3)
        #expect(tokens(ledger).output == 60)

        // Same totals when nothing changed, and when only a duplicate is appended.
        ledger = await scanner.scan(now: now)
        #expect(tokens(ledger).output == 60)
        try append(line("c", output: 30), to: file)
        ledger = await scanner.scan(now: now)
        #expect(tokens(ledger).output == 60)
    }

    @Test func truncatedAndRewrittenFileIsReread() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "s.jsonl")
        let scanner = TranscriptScanner(root: dir, cacheFile: nil)
        try append(line("a", output: 10) + line("b", output: 20) + line("c", output: 30), to: file)
        var ledger = await scanner.scan(now: now)
        #expect(tokens(ledger).output == 60)

        // Shorter content, same inode: size drops below the saved offset.
        try Data().write(to: file)
        try append(line("d", output: 40), to: file)
        ledger = await scanner.scan(now: now)
        #expect(ledger.entries["d"]?.tokens.output == 40)

        // Replaced by a longer file with different content: the head no longer matches.
        let long = (0..<10).map { line("e\($0)", output: 1) }.joined()
        try Data(long.utf8).write(to: file)
        ledger = await scanner.scan(now: now)
        #expect((0..<10).allSatisfy { ledger.entries["e\($0)"] != nil })
        // Re-reading a rewritten file doesn't double count ids already in the ledger.
        #expect(ledger.entries["d"]?.tokens.output == 40)
    }

    @Test func replacedFileWithNewInodeIsReread() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "s.jsonl")
        let scanner = TranscriptScanner(root: dir, cacheFile: nil)
        try append(line("a", output: 10) + line("b", output: 20), to: file)
        _ = await scanner.scan(now: now)
        try FileManager.default.removeItem(at: file)
        try Data((line("a", output: 10) + line("b", output: 20) + line("x", output: 5)).utf8).write(to: file, options: .atomic)
        let ledger = await scanner.scan(now: now)
        #expect(tokens(ledger).output == 35)
    }

    @Test func dropsEntriesOlderThanRetention() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "s.jsonl")
        try append(line("old", offset: -9 * 86400) + line("new", offset: -7 * 86400), to: file)
        let scanner = TranscriptScanner(root: dir, cacheFile: nil)
        var ledger = await scanner.scan(now: now)
        #expect(ledger.entries.keys.sorted() == ["new"])
        // A day later "new" is 8+ days old and is dropped from the ledger.
        ledger = await scanner.scan(now: now.addingTimeInterval(2 * 86400))
        #expect(ledger.count == 0)
    }

    @Test func cachePersistsOffsetsAndLedgerAcrossInstances() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appending(path: "cache/costs.json")
        let projects = dir.appending(path: "projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let file = projects.appending(path: "s.jsonl")
        try append(line("a", output: 10) + line("b", output: 20), to: file)
        _ = await TranscriptScanner(root: projects, cacheFile: cache).scan(now: now)
        #expect(FileManager.default.fileExists(atPath: cache.path))

        // Remove the first lines' source bytes' effect: appending proves the second instance resumes.
        try append(line("c", output: 30), to: file)
        let ledger = await TranscriptScanner(root: projects, cacheFile: cache).scan(now: now)
        #expect(tokens(ledger).output == 60)
    }

    @Test func windowTotalsFromScan() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try append(line("a", offset: -100, output: 1_000_000) + line("b", offset: -10_000, output: 1_000_000), to: dir.appending(path: "s.jsonl"))
        let window = now.addingTimeInterval(-3600)..<now
        let result = await TranscriptScanner(root: dir, cacheFile: nil).scan(now: now, windows: [window])
        #expect(result[0].entryCount == 1)
        #expect(close(result[0].dollars, 25 + 5 / 1e6))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LASTCALL_REAL_SCAN"] != nil))
    func realMachineScan() async throws {
        let env = ProcessInfo.processInfo.environment
        let cache = URL(fileURLWithPath: env["LASTCALL_CACHE_FILE"] ?? NSTemporaryDirectory() + "lastcall-real-cache.json")
        if env["LASTCALL_COLD"] != nil { try? FileManager.default.removeItem(at: cache) }
        let scanner = TranscriptScanner(cacheFile: cache)
        let iso = Date.ISO8601FormatStyle()
        let sessionEnd = try Date("2026-11-03T23:50:00Z", strategy: iso)
        let weekEnd = try Date("2026-11-06T08:00:00Z", strategy: iso)
        let windows = [sessionEnd.addingTimeInterval(-5 * 3600)..<sessionEnd, weekEnd.addingTimeInterval(-7 * 86400)..<weekEnd]
        let clock = ContinuousClock()
        var result: [CostTotals] = []
        let first = await clock.measure { result = await scanner.scan(windows: windows) }
        let second = await clock.measure { _ = await scanner.scan(windows: windows) }
        let size = (try? FileManager.default.attributesOfItem(atPath: cache.path)[.size] as? Int) ?? 0
        print("REALSCAN first=\(first) second=\(second) cacheBytes=\(size) session=\(result[0].dollars) \(result[0].entryCount) unpriced=\(result[0].unpricedTokens) week=\(result[1].dollars) \(result[1].entryCount) unpriced=\(result[1].unpricedTokens)")
    }
}
