import Foundation

/// Pure dosing arithmetic with no SwiftData or UI dependencies, so it can be unit tested.
enum DoseRules {
    static let dailyWindow: TimeInterval = 24 * 3600

    /// Timestamps within the rolling 24 hours ending at `end` (inclusive of `end`).
    static func timestampsInWindow(_ timestamps: [Date], endingAt end: Date) -> [Date] {
        let start = end.addingTimeInterval(-dailyWindow)
        return timestamps.filter { $0 > start && $0 <= end }.sorted()
    }

    /// When the rolling 24 h count next drops below `limit`, or nil if it is already below.
    static func limitResetDate(timestamps: [Date], limit: Int, at now: Date) -> Date? {
        guard limit > 0 else { return nil }
        let recent = timestampsInWindow(timestamps, endingAt: now)
        guard recent.count >= limit else { return nil }
        // To get back to limit - 1 doses, the oldest (count - limit + 1) doses must age out.
        return recent[recent.count - limit].addingTimeInterval(dailyWindow)
    }

    /// How much earlier than allowed a dose was given, or nil if it was on time.
    /// A minute of slack covers doses logged right as the timer finished.
    static func earliness(previous: Date, previousIntervalHours: Double, given: Date) -> TimeInterval? {
        let required = previousIntervalHours * 3600
        let gap = given.timeIntervalSince(previous)
        guard gap < required - 60 else { return nil }
        return required - gap
    }
}

/// Where a child stands against their daily limit for one medication.
struct DailyLimitStatus: Equatable {
    let given: Int
    let limit: Int
    /// When another dose becomes possible again, if the limit is currently reached.
    let resetsAt: Date?

    var isReached: Bool { given >= limit }
}
