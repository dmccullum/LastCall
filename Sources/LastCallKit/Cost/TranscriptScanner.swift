import Foundation

/// Reads Claude Code transcripts under `~/.claude/projects` into a `CostLedger`.
/// Remembers how far it read in each file, so later scans read only appended bytes.
public actor TranscriptScanner {
    struct FileState: Codable, Equatable {
        var inode: UInt64
        var size: Int64
        var mtime: Double
        /// Bytes consumed: everything up to and including the last newline read.
        var offset: Int64
        /// First `min(offset, 64)` bytes, to notice a file rewritten in place.
        var head: Data
    }

    struct Persisted: Codable {
        var version: Int
        var files: [String: FileState]
        var entries: [TranscriptUsage]
    }

    static let formatVersion = 1
    static let headLength = 64
    static let chunkSize = 1 << 20

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)
    }

    public static var defaultCacheFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/com.danielmccullum.LastCall/transcript-costs.json")
    }

    private let root: URL
    private let cacheFile: URL?
    private let retention: TimeInterval
    private var files: [String: FileState] = [:]
    private var ledger = CostLedger()
    private var loaded = false

    public init(root: URL = TranscriptScanner.defaultRoot, cacheFile: URL? = TranscriptScanner.defaultCacheFile, retention: TimeInterval = 8 * 86400) {
        self.root = root
        self.cacheFile = cacheFile
        self.retention = retention
    }

    /// Scans for new transcript bytes and returns the ledger.
    @discardableResult
    public func scan(now: Date = Date()) -> CostLedger {
        loadIfNeeded()
        let cutoff = now.addingTimeInterval(-retention)
        let before = (files, ledger)
        var seen: [String: FileState] = [:]

        for url in transcriptFiles() {
            if Task.isCancelled { break }
            let path = url.path
            guard let info = fileInfo(path) else { continue }
            // Entries can't be newer than the file's last write.
            if Date(timeIntervalSince1970: info.mtime) < cutoff { continue }
            seen[path] = read(path: path, info: info, previous: files[path], cutoff: cutoff)
        }
        if !Task.isCancelled { files = seen }
        ledger.prune(before: cutoff)
        if files != before.0 || ledger != before.1 { persist() }
        return ledger
    }

    /// Scans, then totals each window.
    public func scan(now: Date = Date(), windows: [Range<Date>]) -> [CostTotals] {
        let ledger = scan(now: now)
        return windows.map { ledger.totals(from: $0.lowerBound, to: $0.upperBound) }
    }

    // MARK: Enumeration

    private func transcriptFiles() -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            result.append(url)
        }
        return result
    }

    private struct Info {
        var inode: UInt64
        var size: Int64
        var mtime: Double
    }

    private func fileInfo(_ path: String) -> Info? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        let m = st.st_mtimespec
        return Info(inode: UInt64(st.st_ino), size: Int64(st.st_size), mtime: Double(m.tv_sec) + Double(m.tv_nsec) / 1e9)
    }

    // MARK: Reading

    private func read(path: String, info: Info, previous: FileState?, cutoff: Date) -> FileState? {
        var start: Int64 = 0
        if let previous, previous.inode == info.inode, info.size >= previous.offset {
            if previous.size == info.size, previous.mtime == info.mtime { return previous }
            if headMatches(path: path, previous: previous) { start = previous.offset }
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return previous }
        defer { try? handle.close() }
        var consumed = start
        var carry = Data()
        do {
            try handle.seek(toOffset: UInt64(start))
            while true {
                let more: Bool = try autoreleasepool {
                    guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else { return false }
                    carry.append(chunk)
                    let used = carry.withUnsafeBytes { Self.process($0, cutoff: cutoff, into: &ledger) }
                    if used > 0 {
                        carry = Data(carry[carry.startIndex.advanced(by: used)...])
                        consumed += Int64(used)
                    }
                    return true
                }
                if !more { break }
            }
        } catch {
            // Keep what was consumed; the next scan resumes there.
        }
        let headBytes = min(consumed, Int64(Self.headLength))
        var head = Data()
        if headBytes > 0, let h = FileHandle(forReadingAtPath: path) {
            try? h.seek(toOffset: 0)
            head = (try? h.read(upToCount: Int(headBytes))) ?? Data()
            try? h.close()
        }
        return FileState(inode: info.inode, size: info.size, mtime: info.mtime, offset: consumed, head: head)
    }

    private func headMatches(path: String, previous: FileState) -> Bool {
        if previous.head.isEmpty { return true }
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: previous.head.count)) ?? Data()
        return head == previous.head
    }

    private static let usageNeedle = Array("\"usage\"".utf8)
    private static let stampNeedle = Array("\"timestamp\":\"".utf8)

    /// Handles each complete line in `buffer`. Returns the byte count through the last newline.
    nonisolated static func process(_ buffer: UnsafeRawBufferPointer, cutoff: Date, into ledger: inout CostLedger) -> Int {
        guard let base = buffer.baseAddress else { return 0 }
        let count = buffer.count
        var start = 0
        while start < count, let newline = memchr(base + start, 0x0A, count - start) {
            let end = base.distance(to: UnsafeRawPointer(newline))
            handle(line: base + start, length: end - start, cutoff: cutoff, into: &ledger)
            start = end + 1
        }
        return start
    }

    private nonisolated static func handle(line: UnsafeRawPointer, length: Int, cutoff: Date, into ledger: inout CostLedger) {
        guard length > 20 else { return }
        let hasUsage = usageNeedle.withUnsafeBytes { memmem(line, length, $0.baseAddress, $0.count) != nil }
        guard hasUsage else { return }
        // Cheap age check before the full JSON parse; resumed sessions copy old history.
        let found = stampNeedle.withUnsafeBytes { memmem(line, length, $0.baseAddress, $0.count) }
        if let found {
            let offset = line.distance(to: UnsafeRawPointer(found)) + stampNeedle.count
            if length - offset >= 24 {
                let bytes = UnsafeBufferPointer(start: (line + offset).assumingMemoryBound(to: UInt8.self), count: 24)
                if let date = TimestampParser.parse(bytes: bytes), date < cutoff { return }
            }
        }
        let data = Data(bytes: line, count: length)
        if let usage = TranscriptUsage.parse(line: data), usage.timestamp >= cutoff {
            ledger.insert(usage)
        }
    }

    // MARK: Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let cacheFile, let data = try? Data(contentsOf: cacheFile),
              let saved = try? JSONDecoder().decode(Persisted.self, from: data),
              saved.version == Self.formatVersion
        else { return }
        files = saved.files
        ledger = CostLedger(entries: Dictionary(saved.entries.map { ($0.messageID, $0) }, uniquingKeysWith: { a, _ in a }))
    }

    private func persist() {
        guard let cacheFile else { return }
        let saved = Persisted(version: Self.formatVersion, files: files, entries: Array(ledger.entries.values))
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheFile, options: .atomic)
    }
}
