import Foundation
import Testing
@testable import LastCallKit

@Suite struct FormattingTests {
    let en = Locale(identifier: "en_US")
    let utc = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_793_000_000)  // Thu 2026-10-29 ... any fixed instant

    @Test func countdownHoursAndMinutes() {
        let text = UsageFormat.resetsIn(now.addingTimeInterval(2 * 3600 + 13 * 60 + 20), now: now, locale: en)
        #expect(text == "Resets in 2 hr 13 min")
    }

    @Test func countdownMinutesOnly() {
        #expect(UsageFormat.resetsIn(now.addingTimeInterval(45 * 60), now: now, locale: en) == "Resets in 45 min")
    }

    @Test func countdownExactHour() {
        #expect(UsageFormat.resetsIn(now.addingTimeInterval(3600), now: now, locale: en) == "Resets in 1 hr")
    }

    @Test func countdownUnderAMinute() {
        #expect(UsageFormat.resetsIn(now.addingTimeInterval(59), now: now, locale: en) == "Resets in less than a minute")
        #expect(UsageFormat.resetsIn(now.addingTimeInterval(-5), now: now, locale: en) == "Resets in less than a minute")
    }

    @Test func countdownWithDays() {
        let text = UsageFormat.resetsIn(now.addingTimeInterval(86400 + 3 * 3600 + 600), now: now, locale: en)
        #expect(text == "Resets in 1 day 3 hr")
    }

    @Test func weekdayAndTime() throws {
        let date = try #require(ISODate.parse("2026-11-05T09:00:00Z"))  // a Thursday
        #expect(UsageFormat.resetsOn(date, locale: en, timeZone: utc).plain == "Resets Thu 9:00 AM")
        #expect(UsageFormat.resetsAt(date, locale: en, timeZone: utc).plain == "Resets at 9:00 AM")
    }

    @Test func updatedText() {
        #expect(UsageFormat.updated(now.addingTimeInterval(-20), now: now, locale: en) == "Updated just now")
        #expect(UsageFormat.updated(now.addingTimeInterval(-90), now: now, locale: en) == "Updated 1 min ago")
    }

    @Test func percentRoundsAndClamps() {
        #expect(UsageFormat.percent(41.5) == 42)
        #expect(UsageFormat.percent(-3) == 0)
        #expect(UsageFormat.percent(130) == 100)
    }

    @Test func summarySentence() throws {
        let session = try #require(ISODate.parse("2026-11-03T15:40:00Z"))
        let week = try #require(ISODate.parse("2026-11-05T09:00:00Z"))
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 42, resetsAt: session),
            sevenDay: UsageWindow(utilization: 18, resetsAt: week),
            fetchedAt: now
        )
        #expect(UsageFormat.summary(snapshot, locale: en, timeZone: utc).plain
                == "Session 42%, resets 3:40 PM. Week 18%, resets Thu 9:00 AM.")
    }
}

extension String {
    /// Replaces the narrow no-break space the system puts before AM and PM.
    var plain: String { replacingOccurrences(of: "\u{202F}", with: " ") }
}
