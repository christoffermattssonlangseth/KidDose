import Foundation
import Testing

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
