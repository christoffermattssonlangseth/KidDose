import Foundation

/// One logged dose as seen by the safety rules: when it was given and the gap it requires.
struct DoseRecord: Equatable {
    let timestamp: Date
    let intervalHours: Double

    var clearsAt: Date { timestamp.addingTimeInterval(intervalHours * 3600) }
}

/// Whether a new dose may be given at a given moment, and if not, why.
enum DoseAvailability: Equatable {
    case allowed
    case tooSoon(until: Date)
    case dailyLimitReached(until: Date, limit: Int)

    var isAllowed: Bool { self == .allowed }

    var blockedUntil: Date? {
        switch self {
        case .allowed:                                  return nil
        case let .tooSoon(until):                       return until
        case let .dailyLimitReached(until, _):          return until
        }
    }
}

/// A rule broken by a dose that was already given (past entries, Watch requests).
enum DoseConflict: Equatable {
    case tooCloseToPrevious(previous: Date, requiredGapHours: Double)
    case tooCloseToNext(next: Date, requiredGapHours: Double)
    case exceedsDailyLimit(limit: Int, count: Int)
}

/// Pure dose-safety rules, shared by the Give button, the Watch, past-dose entry,
/// notifications and widgets.
///
/// Deliberately ignores infection cycles and "Dose Skipped": those only change what the
/// card shows. A dose given 30 minutes ago is still in the child's body after either.
enum DoseRules {
    static let dailyWindow: TimeInterval = 24 * 3600

    /// The earliest moment a new dose satisfies both the interval and the 24 h limit.
    /// Nil when no doses have been given.
    static func earliestNextDose(after doses: [DoseRecord], maxDosesPer24h: Int?) -> Date? {
        let newestFirst = doses.sorted { $0.timestamp > $1.timestamp }
        guard let latest = newestFirst.first else { return nil }
        let intervalClears = latest.clearsAt
        guard let limitClears = dailyLimitClearsAt(newestFirst: newestFirst, maxDosesPer24h: maxDosesPer24h) else {
            return intervalClears
        }
        return max(intervalClears, limitClears)
    }

    static func availability(doses: [DoseRecord], maxDosesPer24h: Int?, at now: Date) -> DoseAvailability {
        let newestFirst = doses.sorted { $0.timestamp > $1.timestamp }
        guard let latest = newestFirst.first else { return .allowed }
        let intervalClears = latest.clearsAt

        if
            let limit = maxDosesPer24h,
            let limitClears = dailyLimitClearsAt(newestFirst: newestFirst, maxDosesPer24h: limit),
            now < limitClears,
            limitClears >= intervalClears
        {
            return .dailyLimitReached(until: limitClears, limit: limit)
        }
        if now < intervalClears {
            return .tooSoon(until: intervalClears)
        }
        return .allowed
    }

    /// Doses given in the 24 h ending at `now`.
    static func dosesInLast24h(_ doses: [DoseRecord], at now: Date) -> Int {
        doses.filter { $0.timestamp <= now && now.timeIntervalSince($0.timestamp) < dailyWindow }.count
    }

    /// Rules that `newDose` breaks relative to `existing` doses of the same medication.
    static func conflicts(
        adding newDose: DoseRecord,
        to existing: [DoseRecord],
        maxDosesPer24h: Int?
    ) -> [DoseConflict] {
        var result: [DoseConflict] = []

        let previous = existing
            .filter { $0.timestamp <= newDose.timestamp }
            .max { $0.timestamp < $1.timestamp }
        if let previous, newDose.timestamp < previous.clearsAt {
            result.append(.tooCloseToPrevious(previous: previous.timestamp, requiredGapHours: previous.intervalHours))
        }

        let next = existing
            .filter { $0.timestamp > newDose.timestamp }
            .min { $0.timestamp < $1.timestamp }
        if let next, next.timestamp < newDose.clearsAt {
            result.append(.tooCloseToNext(next: next.timestamp, requiredGapHours: newDose.intervalHours))
        }

        if let limit = maxDosesPer24h, limit > 0 {
            // Check every 24 h window that starts at a dose and contains the new one.
            let timestamps = (existing + [newDose]).map(\.timestamp)
            let busiest = timestamps
                .filter { $0 <= newDose.timestamp && newDose.timestamp.timeIntervalSince($0) < dailyWindow }
                .map { start in
                    timestamps.filter { $0 >= start && $0.timeIntervalSince(start) < dailyWindow }.count
                }
                .max() ?? 0
            if busiest > limit {
                result.append(.exceedsDailyLimit(limit: limit, count: busiest))
            }
        }

        return result
    }

    /// When the oldest dose that keeps the 24 h count at the limit falls out of the window.
    private static func dailyLimitClearsAt(newestFirst: [DoseRecord], maxDosesPer24h: Int?) -> Date? {
        guard let limit = maxDosesPer24h, limit > 0, newestFirst.count >= limit else { return nil }
        return newestFirst[limit - 1].timestamp.addingTimeInterval(dailyWindow)
    }
}

extension DoseConflict {
    func explanation(medicationName: String) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        switch self {
        case let .tooCloseToPrevious(previous, gap):
            return "Less than \(Int(gap)) h after the \(medicationName.lowercased()) dose at \(previous.formatted(time))."
        case let .tooCloseToNext(next, gap):
            return "Less than \(Int(gap)) h before the \(medicationName.lowercased()) dose at \(next.formatted(time))."
        case let .exceedsDailyLimit(limit, count):
            return "\(count) \(medicationName.lowercased()) doses within 24 h — your limit is \(limit)."
        }
    }
}
