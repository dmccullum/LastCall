import Foundation
import Testing
@testable import LastCallKit

@Suite struct DecodingTests {
    let fetched = Date(timeIntervalSince1970: 1_000)

    @Test func decodesAllWindowsAndIgnoresUnknownKeys() throws {
        let json = """
        {
          "five_hour": {"utilization": 42.5, "resets_at": "2026-11-03T20:40:00.123456+00:00"},
          "seven_day": {"utilization": 18, "resets_at": "2026-11-06T14:00:00Z"},
          "seven_day_opus": {"utilization": 7.0, "resets_at": null},
          "seven_day_sonnet": {"utilization": 3, "resets_at": "2026-11-06T14:00:00Z"},
          "extra_usage": {"is_enabled": false}
        }
        """
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8), fetchedAt: fetched)
        #expect(snapshot.fiveHour?.utilization == 42.5)
        #expect(snapshot.sevenDay?.utilization == 18)
        #expect(snapshot.sevenDayOpus?.utilization == 7)
        #expect(snapshot.sevenDayOpus?.resetsAt == nil)
        #expect(snapshot.sevenDaySonnet?.utilization == 3)
        #expect(snapshot.fetchedAt == fetched)
    }

    @Test func nullAndMissingWindowsAreNil() throws {
        let json = #"{"five_hour": null, "seven_day": {"utilization": 10, "resets_at": null}}"#
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8), fetchedAt: fetched)
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.sevenDay?.utilization == 10)
        #expect(snapshot.sevenDayOpus == nil)
        #expect(snapshot.sevenDaySonnet == nil)
    }

    @Test func windowWithNullUtilizationIsNil() throws {
        let json = #"{"five_hour": {"utilization": null, "resets_at": null}}"#
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8), fetchedAt: fetched)
        #expect(snapshot.fiveHour == nil)
    }

    @Test func parsesFractionalAndPlainISODates() throws {
        let plain = try #require(ISODate.parse("2026-11-03T20:40:00Z"))
        let fractional = try #require(ISODate.parse("2026-11-03T20:40:00.500Z"))
        let micro = try #require(ISODate.parse("2026-11-03T20:40:00.123456+00:00"))
        let offset = try #require(ISODate.parse("2026-11-03T15:40:00-05:00"))
        #expect(fractional.timeIntervalSince(plain) == 0.5)
        #expect(abs(micro.timeIntervalSince(plain) - 0.123) < 0.01)
        #expect(offset == plain)
        #expect(ISODate.parse("not a date") == nil)
    }

    @Test func malformedBodyThrows() {
        #expect(throws: (any Error).self) {
            try UsageSnapshot.decode(from: Data("[]".utf8), fetchedAt: fetched)
        }
    }
}
