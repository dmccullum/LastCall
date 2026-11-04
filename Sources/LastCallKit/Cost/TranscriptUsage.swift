import Foundation

/// The billable part of one assistant message in a Claude Code transcript.
public struct TranscriptUsage: Codable, Equatable, Sendable {
    public var messageID: String
    public var model: String
    public var timestamp: Date
    public var tokens: TokenCounts
    public var fast: Bool
    public var usGeo: Bool

    public init(messageID: String, model: String, timestamp: Date, tokens: TokenCounts, fast: Bool = false, usGeo: Bool = false) {
        self.messageID = messageID
        self.model = model
        self.timestamp = timestamp
        self.tokens = tokens
        self.fast = fast
        self.usGeo = usGeo
    }

    /// Decodes one JSONL line. Returns nil for lines without `message.usage`, synthetic
    /// messages, or lines missing a timestamp or message id. Unknown fields are ignored.
    public static func parse(line: Data) -> TranscriptUsage? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = object["timestamp"] as? String,
              let timestamp = TimestampParser.parse(stamp)
        else { return nil }
        let model = (message["model"] as? String) ?? "unknown"
        guard model != "<synthetic>" else { return nil }
        guard let id = (message["id"] as? String) ?? (object["requestId"] as? String) else { return nil }

        var tokens = TokenCounts()
        tokens.input = int(usage["input_tokens"])
        tokens.output = int(usage["output_tokens"])
        tokens.cacheRead = int(usage["cache_read_input_tokens"])
        let created = int(usage["cache_creation_input_tokens"])
        if let split = usage["cache_creation"] as? [String: Any] {
            tokens.cacheWrite1h = int(split["ephemeral_1h_input_tokens"])
            tokens.cacheWrite5m = int(split["ephemeral_5m_input_tokens"])
            if tokens.cacheWrite1h + tokens.cacheWrite5m == 0 { tokens.cacheWrite5m = created }
        } else {
            tokens.cacheWrite5m = created
        }
        return TranscriptUsage(
            messageID: id, model: model, timestamp: timestamp, tokens: tokens,
            fast: (usage["speed"] as? String) == "fast",
            usGeo: (usage["inference_geo"] as? String) == "us"
        )
    }

    public static func parse(line: String) -> TranscriptUsage? {
        parse(line: Data(line.utf8))
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}

enum TimestampParser {
    /// Parses `YYYY-MM-DDTHH:MM:SS[.fff]Z` without allocating; other forms fall back to Foundation.
    static func parse(_ string: String) -> Date? {
        var copy = string
        let fast = copy.withUTF8 { parse(bytes: $0) }
        if let fast { return fast }
        if let date = try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) {
            return date
        }
        return try? Date(string, strategy: .iso8601)
    }

    static func parse(bytes b: UnsafeBufferPointer<UInt8>) -> Date? {
        guard b.count >= 20, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A else { return nil }
        func digits(_ from: Int, _ count: Int) -> Int? {
            var value = 0
            for i in from..<(from + count) {
                let d = Int(b[i]) - 0x30
                guard d >= 0, d <= 9 else { return nil }
                value = value * 10 + d
            }
            return value
        }
        guard let y = digits(0, 4), let mo = digits(5, 2), let d = digits(8, 2),
              let h = digits(11, 2), let mi = digits(14, 2), let s = digits(17, 2),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 61
        else { return nil }
        var index = 19
        var fraction = 0.0
        if index < b.count, b[index] == 0x2E {
            index += 1
            var scale = 0.1
            while index < b.count, b[index] >= 0x30, b[index] <= 9 + 0x30 {
                fraction += Double(b[index] - 0x30) * scale
                scale /= 10
                index += 1
            }
        }
        guard index < b.count, b[index] == 0x5A, index == b.count - 1 else { return nil }
        // Days from civil (Howard Hinnant).
        let yy = mo <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        let seconds = Double(days) * 86400 + Double(h * 3600 + mi * 60 + s) + fraction
        return Date(timeIntervalSince1970: seconds)
    }
}
