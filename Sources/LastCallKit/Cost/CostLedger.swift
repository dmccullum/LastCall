import Foundation

public struct CostTotals: Equatable, Sendable {
    public var dollars = 0.0
    /// Tokens of every entry in range, priced or not.
    public var tokens = TokenCounts()
    /// Tokens of entries whose model has no price.
    public var unpricedTokens = 0
    public var entryCount = 0

    public init() {}

    public var hasUnpriced: Bool { unpricedTokens > 0 }
}

/// What the UI shows for one window.
public struct CostEstimate: Equatable, Sendable {
    public var dollars: Double
    public var hasUnpriced: Bool

    public init(dollars: Double, hasUnpriced: Bool) {
        self.dollars = dollars
        self.hasUnpriced = hasUnpriced
    }

    public init(_ totals: CostTotals) {
        self.init(dollars: totals.dollars, hasUnpriced: totals.hasUnpriced)
    }

    /// “≈ $18.40 API equivalent”, with “ · partial” when some models had no price.
    public var caption: String {
        let amount = dollars.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(2)))
        return "≈ \(amount) API equivalent" + (hasUnpriced ? " · partial" : "")
    }
}

/// Usage records keyed by message id. One API response is written once per content block,
/// and resumed sessions copy history, so the same id shows up many times.
public struct CostLedger: Equatable, Sendable {
    public private(set) var entries: [String: TranscriptUsage]

    public init(entries: [String: TranscriptUsage] = [:]) {
        self.entries = entries
    }

    public var count: Int { entries.count }

    /// Keeps the entry with the most output tokens, stamped with the earliest timestamp seen.
    public mutating func insert(_ usage: TranscriptUsage) {
        guard let existing = entries[usage.messageID] else {
            entries[usage.messageID] = usage
            return
        }
        var kept = usage.tokens.output > existing.tokens.output ? usage : existing
        kept.timestamp = min(existing.timestamp, usage.timestamp)
        entries[usage.messageID] = kept
    }

    public mutating func prune(before cutoff: Date) {
        entries = entries.filter { $0.value.timestamp >= cutoff }
    }

    /// Totals for entries with `start <= timestamp < end`.
    public func totals(from start: Date, to end: Date) -> CostTotals {
        var totals = CostTotals()
        for usage in entries.values where usage.timestamp >= start && usage.timestamp < end {
            totals.entryCount += 1
            totals.tokens += usage.tokens
            if let cost = APIPricing.cost(of: usage) {
                totals.dollars += cost
            } else {
                totals.unpricedTokens += usage.tokens.total
            }
        }
        return totals
    }
}
