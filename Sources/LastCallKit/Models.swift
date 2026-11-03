import Foundation

/// One rate-limit window from the usage endpoint.
public struct UsageWindow: Equatable, Sendable {
    /// Percent used, 0 to 100.
    public var utilization: Double
    public var resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
    public var sevenDayOpus: UsageWindow?
    public var sevenDaySonnet: UsageWindow?
    public var fetchedAt: Date

    public init(
        fiveHour: UsageWindow? = nil,
        sevenDay: UsageWindow? = nil,
        sevenDayOpus: UsageWindow? = nil,
        sevenDaySonnet: UsageWindow? = nil,
        fetchedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.fetchedAt = fetchedAt
    }

    /// Decodes the body of GET /api/oauth/usage. Windows that are null, missing or
    /// have no utilization become nil; unknown keys are ignored.
    public static func decode(from data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return UsageSnapshot(
            fiveHour: response.fiveHour?.window,
            sevenDay: response.sevenDay?.window,
            sevenDayOpus: response.sevenDayOpus?.window,
            sevenDaySonnet: response.sevenDaySonnet?.window,
            fetchedAt: fetchedAt
        )
    }

    private struct Response: Decodable {
        var fiveHour: RawWindow?
        var sevenDay: RawWindow?
        var sevenDayOpus: RawWindow?
        var sevenDaySonnet: RawWindow?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
        }
    }

    private struct RawWindow: Decodable {
        var utilization: Double?
        var resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        var window: UsageWindow? {
            guard let utilization else { return nil }
            return UsageWindow(utilization: utilization, resetsAt: resetsAt.flatMap(ISODate.parse))
        }
    }
}

public enum ISODate {
    /// Parses ISO 8601 with or without fractional seconds.
    public static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

public enum UsageError: Error, Equatable, Sendable {
    /// No usable credentials, or the refresh token was rejected.
    case signedOut
    /// The access token was rejected (HTTP 401).
    case unauthorized
    case network
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case unreadableResponse
    case keychain
}
