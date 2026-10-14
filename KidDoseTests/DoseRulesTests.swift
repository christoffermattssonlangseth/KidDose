import Foundation
import Testing
import XCTest
@testable import KidDose

/// Doses are placed relative to a fixed `now` so tests don't depend on the clock.
private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func hours(_ value: Double) -> Date {
    now.addingTimeInterval(value * 3600)
}

private func dose(at offsetHours: Double, every intervalHours: Double = 6) -> DoseRecord {
    DoseRecord(timestamp: hours(offsetHours), intervalHours: intervalHours)
}

struct DoseAvailabilityTests {
    @Test func noDosesIsAllowed() {
        #expect(DoseRules.availability(doses: [], maxDosesPer24h: 4, at: now) == .allowed)
        #expect(DoseRules.earliestNextDose(after: [], maxDosesPer24h: 4) == nil)
    }

    @Test func tooSoonUntilLatestDoseInterval() {
        let doses = [dose(at: -10), dose(at: -2)]
        #expect(DoseRules.availability(doses: doses, maxDosesPer24h: nil, at: now) == .tooSoon(until: hours(4)))
    }

    @Test func allowedOnceIntervalHasPassed() {
        #expect(DoseRules.availability(doses: [dose(at: -7)], maxDosesPer24h: nil, at: now) == .allowed)
    }

    @Test func exactlyAtIntervalIsAllowed() {
        #expect(DoseRules.availability(doses: [dose(at: -6)], maxDosesPer24h: nil, at: now) == .allowed)
    }

    @Test func usesLatestDoseOwnInterval() {
        // Ibuprofen switched to 8 h on the latest dose.
        let doses = [dose(at: -12, every: 6), dose(at: -7, every: 8)]
        #expect(DoseRules.availability(doses: doses, maxDosesPer24h: nil, at: now) == .tooSoon(until: hours(1)))
    }

    @Test func orderOfInputDoesNotMatter() {
        let doses = [dose(at: -2), dose(at: -10)]
        #expect(DoseRules.availability(doses: doses, maxDosesPer24h: nil, at: now) == .tooSoon(until: hours(4)))
    }

    @Test func dailyLimitBlocksBeyondInterval() {
        // Three doses in 24 h with a limit of 3: the interval clears in 4 h, but the
        // oldest of the three only leaves the 24 h window in 10 h.
        let doses = [dose(at: -14), dose(at: -8), dose(at: -2)]
        #expect(
            DoseRules.availability(doses: doses, maxDosesPer24h: 3, at: now)
                == .dailyLimitReached(until: hours(10), limit: 3)
        )
        #expect(DoseRules.earliestNextDose(after: doses, maxDosesPer24h: 3) == hours(10))
    }

    @Test func dailyLimitBlocksEvenWhenIntervalIsClear() {
        let doses = [dose(at: -20), dose(at: -14), dose(at: -8)]
        #expect(
            DoseRules.availability(doses: doses, maxDosesPer24h: 3, at: now)
                == .dailyLimitReached(until: hours(4), limit: 3)
        )
    }

    @Test func dosesOlderThan24hDoNotCountTowardLimit() {
        let doses = [dose(at: -40), dose(at: -34), dose(at: -28), dose(at: -7)]
        #expect(DoseRules.availability(doses: doses, maxDosesPer24h: 3, at: now) == .allowed)
    }

    @Test func intervalWinsWhenItClearsLater() {
        let doses = [dose(at: -23), dose(at: -2)]
        #expect(DoseRules.availability(doses: doses, maxDosesPer24h: 2, at: now) == .tooSoon(until: hours(4)))
    }

    @Test func earliestNextDoseMatchesBlockedUntil() {
        let doses = [dose(at: -15), dose(at: -9), dose(at: -3)]
        let availability = DoseRules.availability(doses: doses, maxDosesPer24h: 3, at: now)
        #expect(availability.blockedUntil == DoseRules.earliestNextDose(after: doses, maxDosesPer24h: 3))
    }

    @Test func countsDosesInLast24h() {
        let doses = [dose(at: -30), dose(at: -24), dose(at: -23.9), dose(at: -1), dose(at: 1)]
        #expect(DoseRules.dosesInLast24h(doses, at: now) == 2)
    }
}

struct DoseConflictTests {
    @Test func wellSpacedPastDoseHasNoConflicts() {
        let existing = [dose(at: -20), dose(at: -2)]
        let past = dose(at: -12)
        #expect(DoseRules.conflicts(adding: past, to: existing, maxDosesPer24h: 4).isEmpty)
    }

    @Test func pastDoseTooSoonAfterPrevious() {
        let existing = [dose(at: -10)]
        let past = dose(at: -7)
        #expect(
            DoseRules.conflicts(adding: past, to: existing, maxDosesPer24h: nil)
                == [.tooCloseToPrevious(previous: hours(-10), requiredGapHours: 6)]
        )
    }

    @Test func pastDoseTooCloseToNewerDose() {
        // A partner logged at -2 h; back-filling a dose at -5 h makes their dose too early.
        let existing = [dose(at: -2)]
        let past = dose(at: -5)
        #expect(
            DoseRules.conflicts(adding: past, to: existing, maxDosesPer24h: nil)
                == [.tooCloseToNext(next: hours(-2), requiredGapHours: 6)]
        )
    }

    @Test func watchDoseRightAfterPartnerDose() {
        let existing = [dose(at: -0.5)]
        let watchDose = dose(at: 0)
        #expect(
            DoseRules.conflicts(adding: watchDose, to: existing, maxDosesPer24h: nil)
                == [.tooCloseToPrevious(previous: hours(-0.5), requiredGapHours: 6)]
        )
    }

    @Test func pastDoseExceedingDailyLimit() {
        let existing = [dose(at: -18), dose(at: -12), dose(at: -6)]
        let past = dose(at: -24.1)  // 6.1 h before the next dose, but makes four within 24 h
        let conflicts = DoseRules.conflicts(adding: past, to: existing, maxDosesPer24h: 3)
        #expect(conflicts == [.exceedsDailyLimit(limit: 3, count: 4)])
    }

    @Test func dailyLimitIgnoresDosesOutsideAnyShared24hWindow() {
        let existing = [dose(at: -60), dose(at: -54), dose(at: -48)]
        let past = dose(at: -12)
        #expect(DoseRules.conflicts(adding: past, to: existing, maxDosesPer24h: 3).isEmpty)
    }
}

// MARK: - Timestamp helpers

final class DoseRulesHelperTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func hoursAgo(_ hours: Double) -> Date {
        now.addingTimeInterval(-hours * 3600)
    }

    func testWindowIncludesEndAndExcludesExactly24HoursAgo() {
        let timestamps = [hoursAgo(24), hoursAgo(23.9), hoursAgo(0), now.addingTimeInterval(60)]
        let inWindow = DoseRules.timestampsInWindow(timestamps, endingAt: now)
        XCTAssertEqual(inWindow, [hoursAgo(23.9), hoursAgo(0)])
    }

    func testLimitResetIsNilWhileBelowLimit() {
        let timestamps = [hoursAgo(10), hoursAgo(2)]
        XCTAssertNil(DoseRules.limitResetDate(timestamps: timestamps, limit: 3, at: now))
    }

    func testLimitResetWhenLimitReached() {
        let timestamps = [hoursAgo(20), hoursAgo(10), hoursAgo(2)]
        let reset = DoseRules.limitResetDate(timestamps: timestamps, limit: 3, at: now)
        // The oldest dose ages out 24 h after it was given, 4 h from now.
        XCTAssertEqual(reset, hoursAgo(20).addingTimeInterval(24 * 3600))
    }

    func testLimitResetWhenOverLimitWaitsForEnoughDosesToAgeOut() {
        let timestamps = [hoursAgo(22), hoursAgo(15), hoursAgo(8), hoursAgo(1)]
        let reset = DoseRules.limitResetDate(timestamps: timestamps, limit: 3, at: now)
        // 4 doses with a limit of 3: two must age out to get back to 2.
        XCTAssertEqual(reset, hoursAgo(15).addingTimeInterval(24 * 3600))
    }

    func testZeroLimitMeansNoLimit() {
        XCTAssertNil(DoseRules.limitResetDate(timestamps: [hoursAgo(1)], limit: 0, at: now))
    }

    func testEarlinessReportsHowEarly() throws {
        let early = try XCTUnwrap(DoseRules.earliness(previous: hoursAgo(6), previousIntervalHours: 8, given: now))
        XCTAssertEqual(early, 2 * 3600, accuracy: 0.5)
    }

    func testEarlinessAllowsAMinuteOfSlack() {
        let given = hoursAgo(8).addingTimeInterval(8 * 3600 - 30)
        XCTAssertNil(DoseRules.earliness(previous: hoursAgo(8), previousIntervalHours: 8, given: given))
    }

    func testDailyLimitStatusIsReached() {
        XCTAssertTrue(DailyLimitStatus(given: 4, limit: 4, resetsAt: nil).isReached)
        XCTAssertFalse(DailyLimitStatus(given: 3, limit: 4, resetsAt: nil).isReached)
    }
}
