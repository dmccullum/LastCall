import Foundation
import Testing
@testable import LastCallKit

@Suite struct PaceTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func elapsedFractionOfFiveHourWindow() {
        let reset = now.addingTimeInterval(2.5 * 3600)
        #expect(PaceMath.elapsedFraction(resetsAt: reset, now: now, kind: .fiveHour) == 0.5)
        #expect(PaceMath.elapsedFraction(resetsAt: now.addingTimeInterval(5 * 3600), now: now, kind: .fiveHour) == 0)
    }

    @Test func elapsedFractionOfWeeklyWindow() {
        let reset = now.addingTimeInterval(7 * 86400 / 4)
        #expect(abs(PaceMath.elapsedFraction(resetsAt: reset, now: now, kind: .weekly) - 0.75) < 1e-9)
    }

    @Test func elapsedFractionClamps() {
        #expect(PaceMath.elapsedFraction(resetsAt: now.addingTimeInterval(-10), now: now, kind: .fiveHour) == 1)
        #expect(PaceMath.elapsedFraction(resetsAt: now.addingTimeInterval(99 * 3600), now: now, kind: .fiveHour) == 0)
    }

    @Test func paceUsesFivePointTolerance() {
        #expect(PaceMath.pace(utilizationPercent: 56, elapsedFraction: 0.5) == .ahead)
        #expect(PaceMath.pace(utilizationPercent: 55, elapsedFraction: 0.5) == .onPace)
        #expect(PaceMath.pace(utilizationPercent: 50, elapsedFraction: 0.5) == .onPace)
        #expect(PaceMath.pace(utilizationPercent: 45, elapsedFraction: 0.5) == .onPace)
        #expect(PaceMath.pace(utilizationPercent: 44, elapsedFraction: 0.5) == .behind)
        #expect(PaceMath.pace(utilizationPercent: 0, elapsedFraction: 0) == .onPace)
    }

    @Test func paceTitles() {
        #expect(Pace.ahead.title == "Ahead of pace")
        #expect(Pace.onPace.title == "On pace")
        #expect(Pace.behind.title == "Behind pace")
    }
}
