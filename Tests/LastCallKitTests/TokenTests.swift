import Foundation
import Testing
@testable import LastCallKit

@Suite struct TokenTests {
    let now = Date(timeIntervalSince1970: 2_000_000)
    func ms(_ offset: TimeInterval) -> Double { (now.timeIntervalSince1970 + offset) * 1000 }

    @Test func zeroOrMissingExpiryRefreshes() {
        #expect(TokenPolicy.needsRefresh(expiresAtMs: 0, now: now))
        #expect(TokenPolicy.needsRefresh(expiresAtMs: nil, now: now))
    }

    @Test func expiredRefreshes() {
        #expect(TokenPolicy.needsRefresh(expiresAtMs: ms(-1), now: now))
    }

    @Test func withinFiveMinutesRefreshes() {
        #expect(TokenPolicy.needsRefresh(expiresAtMs: ms(299), now: now))
        #expect(TokenPolicy.needsRefresh(expiresAtMs: ms(300), now: now))
    }

    @Test func beyondFiveMinutesKeepsToken() {
        #expect(!TokenPolicy.needsRefresh(expiresAtMs: ms(301), now: now))
        #expect(!TokenPolicy.needsRefresh(expiresAtMs: ms(8 * 3600), now: now))
    }

    @Test func parsesCredentialJSONAndKeepsUnknownKeys() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r","expiresAt":123,"scopes":["x"],"subscriptionType":"max","rateLimitTier":"t"},"other":{"k":1}}"#
        let creds = try #require(StoredCredentials(json: Data(json.utf8)))
        #expect(creds.accessToken == "a")
        #expect(creds.refreshToken == "r")
        #expect(creds.expiresAtMs == 123)

        let renewed = try #require(creds.replacingTokens(accessToken: "a2", refreshToken: "r2", expiresAtMs: 456_000))
        #expect(renewed.accessToken == "a2")
        #expect(renewed.refreshToken == "r2")
        #expect(renewed.expiresAtMs == 456_000)
        let root = try #require(JSONSerialization.jsonObject(with: renewed.json) as? [String: Any])
        let oauth = try #require(root["claudeAiOauth"] as? [String: Any])
        #expect(oauth["subscriptionType"] as? String == "max")
        #expect(oauth["rateLimitTier"] as? String == "t")
        #expect(oauth["scopes"] as? [String] == ["x"])
        #expect((root["other"] as? [String: Any])?["k"] as? Int == 1)
    }

    @Test func rejectsJSONWithoutOAuthBlock() {
        #expect(StoredCredentials(json: Data("{}".utf8)) == nil)
        #expect(StoredCredentials(json: Data("nope".utf8)) == nil)
    }
}

/// An in-memory store and scripted transport for the service flow.
final class MemoryStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private(set) var writes = 0
    init(_ json: String?) { data = json.map { Data($0.utf8) } }
    func read() async throws -> Data? { lock.withLock { data } }
    func write(_ json: Data) async throws { lock.withLock { data = json; writes += 1 } }
}

final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Int, String)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock { () -> (Int, String) in
            requests.append(request)
            return responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@Suite struct ServiceTests {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let usageBody = #"{"five_hour":{"utilization":10,"resets_at":null}}"#

    func credentials(expiresInSeconds: Double) -> String {
        let ms = Int64((2_000_000 + expiresInSeconds) * 1000)
        return #"{"claudeAiOauth":{"accessToken":"old","refreshToken":"rt1","expiresAt":\#(ms),"scopes":["s"]}}"#
    }

    @Test func refreshesExpiredTokenAndWritesBack() async throws {
        let store = MemoryStore(credentials(expiresInSeconds: 0))
        let transport = ScriptedTransport([
            (200, #"{"access_token":"new","refresh_token":"rt2","expires_in":3600}"#),
            (200, usageBody)
        ])
        let service = UsageService(store: store, transport: transport, now: { Date(timeIntervalSince1970: 2_000_000) })
        let snapshot = try await service.fetchUsage()
        #expect(snapshot.fiveHour?.utilization == 10)
        #expect(transport.requests.count == 2)
        #expect(transport.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer new")
        #expect(store.writes == 1)
        let savedData = try #require(await store.read())
        let saved = try #require(StoredCredentials(json: savedData))
        #expect(saved.refreshToken == "rt2")
    }

    @Test func retriesOnceAfter401() async throws {
        let store = MemoryStore(credentials(expiresInSeconds: 3600))
        let transport = ScriptedTransport([
            (401, "{}"),
            (200, #"{"access_token":"new","refresh_token":"rt2","expires_in":3600}"#),
            (200, usageBody)
        ])
        let service = UsageService(store: store, transport: transport, now: { Date(timeIntervalSince1970: 2_000_000) })
        _ = try await service.fetchUsage()
        #expect(transport.requests.count == 3)
    }

    @Test func secondUnauthorizedIsSignedOut() async {
        let store = MemoryStore(credentials(expiresInSeconds: 3600))
        let transport = ScriptedTransport([
            (401, "{}"),
            (200, #"{"access_token":"new","expires_in":3600}"#),
            (401, "{}")
        ])
        let service = UsageService(store: store, transport: transport, now: { Date(timeIntervalSince1970: 2_000_000) })
        await #expect(throws: UsageError.signedOut) { try await service.fetchUsage() }
    }

    @Test func missingItemIsSignedOut() async {
        let service = UsageService(store: MemoryStore(nil), transport: ScriptedTransport([]))
        await #expect(throws: UsageError.signedOut) { try await service.fetchUsage() }
    }

    @Test func rateLimitSurfaces() async {
        let store = MemoryStore(credentials(expiresInSeconds: 3600))
        let transport = ScriptedTransport([(429, "{}")])
        let service = UsageService(store: store, transport: transport, now: { Date(timeIntervalSince1970: 2_000_000) })
        await #expect(throws: UsageError.rateLimited(retryAfter: nil)) { try await service.fetchUsage() }
    }
}

@Suite struct AlertTests {
    let utc = TimeZone(identifier: "UTC")!
    let en = Locale(identifier: "en_US")
    let reset1 = ISODate.parse("2026-11-03T15:40:00Z")!
    let reset2 = ISODate.parse("2026-11-03T20:40:00Z")!
    let all = AlertSettings(session80: true, session95: true, sessionReset: true, weekly80: true)

    func snap(_ session: Double, reset: Date?, week: Double = 0) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: UsageWindow(utilization: session, resetsAt: reset),
            sevenDay: UsageWindow(utilization: week, resetsAt: reset2),
            fetchedAt: .now
        )
    }

    @Test func firesEightyOncePerWindow() {
        let first = AlertPlanner.alerts(previous: nil, current: snap(81, reset: reset1), settings: all, fired: [], locale: en, timeZone: utc)
        #expect(first.count == 1)
        #expect(first[0].message.plain == "Session at 81%. Resets at 3:40 PM.")
        let again = AlertPlanner.alerts(previous: nil, current: snap(82, reset: reset1), settings: all, fired: [first[0].key], locale: en, timeZone: utc)
        #expect(again.isEmpty)
        let nextWindow = AlertPlanner.alerts(previous: nil, current: snap(82, reset: reset2), settings: all, fired: [first[0].key], locale: en, timeZone: utc)
        #expect(nextWindow.count == 1)
    }

    @Test func jumpPastNinetyFiveSendsOne() {
        let alerts = AlertPlanner.alerts(previous: nil, current: snap(96, reset: reset1), settings: all, fired: [], locale: en, timeZone: utc)
        #expect(alerts.map(\.message.plain) == ["Session at 96%. Resets at 3:40 PM."])
    }

    @Test func resetFiresOnlyAfterEightyOrMore() {
        let high = AlertPlanner.alerts(previous: snap(85, reset: reset1), current: snap(2, reset: reset2), settings: all, fired: [], locale: en, timeZone: utc)
        #expect(high.contains { $0.key.hasPrefix("sr|") })
        let low = AlertPlanner.alerts(previous: snap(50, reset: reset1), current: snap(2, reset: reset2), settings: all, fired: [], locale: en, timeZone: utc)
        #expect(!low.contains { $0.key.hasPrefix("sr|") })
    }

    @Test func disabledSettingsSendNothing() {
        let alerts = AlertPlanner.alerts(previous: nil, current: snap(99, reset: reset1, week: 90), settings: AlertSettings(), fired: [], locale: en, timeZone: utc)
        #expect(alerts.isEmpty)
    }

    @Test func weeklyEighty() {
        let alerts = AlertPlanner.alerts(previous: nil, current: snap(10, reset: reset1, week: 80), settings: all, fired: [], locale: en, timeZone: utc)
        #expect(alerts.map(\.message.plain) == ["Weekly limit at 80%. Resets Tue 8:40 PM."])
    }
}
