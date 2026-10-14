import XCTest
@testable import KidDose

final class DoseRulesTests: XCTestCase {
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
