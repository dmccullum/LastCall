import Foundation

/// Token counts by billing category.
public struct TokenCounts: Codable, Equatable, Sendable {
    public var input = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0
    public var cacheRead = 0
    public var output = 0

    public init(input: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.output = output
    }

    public var total: Int { input + cacheWrite5m + cacheWrite1h + cacheRead + output }
    /// Everything the request sent to the model: input plus cache writes and reads.
    public var prompt: Int { input + cacheWrite5m + cacheWrite1h + cacheRead }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs.input += rhs.input
        lhs.cacheWrite5m += rhs.cacheWrite5m
        lhs.cacheWrite1h += rhs.cacheWrite1h
        lhs.cacheRead += rhs.cacheRead
        lhs.output += rhs.output
    }
}

/// USD per million tokens.
public struct Rates: Equatable, Sendable {
    public var input: Double
    public var write5m: Double
    public var write1h: Double
    public var read: Double
    public var output: Double

    public init(_ input: Double, _ write5m: Double, _ write1h: Double, _ read: Double, _ output: Double) {
        self.input = input
        self.write5m = write5m
        self.write1h = write1h
        self.read = read
        self.output = output
    }
}

public struct ModelPrice: Sendable {
    public var prefix: String
    public var standard: Rates
    /// Fast-mode rates; nil when the model has no fast mode (standard rates apply).
    public var fast: Rates?
    /// Rates used when the prompt exceeds `threshold` tokens.
    public var longPrompt: (threshold: Int, rates: Rates)?
    /// True for 4.6+ models, where `inference_geo: "us"` costs 1.1x on every category.
    public var usGeoMultiplier: Bool
}

public enum APIPricing {
    static let usGeoFactor = 1.1

    // Source: https://platform.claude.com/docs/en/about-claude/pricing
    // Fetched: 2026-11-03.
    // Columns: input / 5m cache write / 1h cache write / cache read / output, USD per million tokens.
    public static let table: [ModelPrice] = [
        entry("claude-fable-5-1", Rates(10, 12.5, 20, 0.25, 50), geo: true),
        entry("claude-mythos-5-1", Rates(10, 12.5, 20, 0.25, 50), geo: true),
        entry("claude-fable-5", Rates(10, 12.5, 20, 1, 50), geo: true),
        entry("claude-mythos-5", Rates(10, 12.5, 20, 1, 50), geo: true),
        entry("claude-opus-5-5", Rates(4, 5, 8, 0.2, 20), fast: Rates(8, 10, 16, 0.4, 40), geo: true),
        entry("claude-opus-5", Rates(5, 6.25, 10, 0.5, 25), fast: Rates(10, 12.5, 20, 1, 50), geo: true),
        entry("claude-opus-4-8", Rates(5, 6.25, 10, 0.5, 25), fast: Rates(10, 12.5, 20, 1, 50), geo: true),
        entry("claude-opus-4-7", Rates(5, 6.25, 10, 0.5, 25), geo: true),
        entry("claude-opus-4-6", Rates(5, 6.25, 10, 0.5, 25), geo: true),
        entry("claude-opus-4-5", Rates(5, 6.25, 10, 0.5, 25)),
        entry("claude-opus-4-1", Rates(15, 18.75, 30, 1.5, 75)),
        entry("claude-opus-4", Rates(15, 18.75, 30, 1.5, 75)),
        entry("claude-sonnet-5-5", Rates(2, 2.5, 4, 0.1, 10), geo: true),
        entry("claude-sonnet-5", Rates(2, 2.5, 4, 0.2, 10), geo: true),
        entry("claude-sonnet-4-6", Rates(3, 3.75, 6, 0.3, 15), geo: true),
        entry("claude-sonnet-4-5", Rates(3, 3.75, 6, 0.3, 15)),
        entry("claude-sonnet-4", Rates(3, 3.75, 6, 0.3, 15)),
        entry(
            "claude-haiku-5-5", Rates(0.10, 0.125, 0.20, 0.01, 0.50),
            long: (100_000, Rates(0.50, 0.625, 1, 0.05, 2.50)), geo: true
        ),
        entry("claude-haiku-4-5", Rates(1, 1.25, 2, 0.1, 5)),
        entry("claude-3-5-haiku", Rates(0.80, 1, 1.60, 0.08, 4)),
        entry("claude-haiku-3-5", Rates(0.80, 1, 1.60, 0.08, 4))
    ]

    private static func entry(
        _ prefix: String, _ standard: Rates, fast: Rates? = nil,
        long: (Int, Rates)? = nil, geo: Bool = false
    ) -> ModelPrice {
        ModelPrice(prefix: prefix, standard: standard, fast: fast, longPrompt: long.map { ($0.0, $0.1) }, usGeoMultiplier: geo)
    }

    /// Strips a `[1m]`-style suffix and a trailing `-YYYYMMDD` date.
    public static func normalize(_ model: String) -> String {
        var id = model.lowercased()
        if let bracket = id.firstIndex(of: "[") { id = String(id[..<bracket]) }
        if id.count > 9, let dash = id.lastIndex(of: "-") {
            let tail = id[id.index(after: dash)...]
            if tail.count == 8, tail.allSatisfy(\.isNumber) { id = String(id[..<dash]) }
        }
        return id
    }

    /// Longest table prefix that matches at a segment boundary. A numeric segment after
    /// the prefix (`claude-opus-4-10` vs `claude-opus-4`) is a different model, not a match.
    public static func price(for model: String) -> ModelPrice? {
        let id = normalize(model)
        var best: ModelPrice?
        for candidate in table {
            let prefix = candidate.prefix
            let matches: Bool
            if id == prefix {
                matches = true
            } else if id.hasPrefix(prefix + "-") {
                let rest = id.dropFirst(prefix.count + 1)
                let segment = rest.prefix { $0 != "-" }
                matches = !segment.isEmpty && !segment.allSatisfy(\.isNumber)
            } else {
                matches = false
            }
            if matches, best == nil || prefix.count > best!.prefix.count { best = candidate }
        }
        return best
    }

    /// Dollars for one usage record, or nil when the model has no price.
    public static func cost(of usage: TranscriptUsage) -> Double? {
        guard let price = price(for: usage.model) else { return nil }
        let t = usage.tokens
        var rates = price.standard
        if usage.fast, let fast = price.fast { rates = fast }
        if let long = price.longPrompt, t.prompt > long.threshold { rates = long.rates }
        var dollars = Double(t.input) * rates.input
            + Double(t.cacheWrite5m) * rates.write5m
            + Double(t.cacheWrite1h) * rates.write1h
            + Double(t.cacheRead) * rates.read
            + Double(t.output) * rates.output
        dollars /= 1_000_000
        if usage.usGeo, price.usGeoMultiplier { dollars *= usGeoFactor }
        return dollars
    }
}
