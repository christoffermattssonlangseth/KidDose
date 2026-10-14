import Foundation

/// Snapshot of a single child's dose state, written by the main app and read by the widget extension.
struct WidgetChildSnapshot: Codable, Identifiable {
    var id: String { childID ?? name }
    /// Stable child ID. Optional so snapshots from older builds still decode.
    let childID: String?
    let name: String
    let colorHex: String
    /// The absolute date when the next ibuprofen dose is allowed. Nil if no doses recorded or session ended.
    let ibuprofenNextDate: Date?
    /// The absolute date when the next paracetamol dose is allowed. Nil if no doses recorded or session ended.
    let paracetamolNextDate: Date?
    /// True if at least one ibuprofen dose exists in the current cycle.
    let ibuprofenHasDoses: Bool
    /// True if at least one paracetamol dose exists in the current cycle.
    let paracetamolHasDoses: Bool
    /// True when the parent marked the ibuprofen course as skipped/ended ("Dose Skipped" on Home).
    /// Optional so snapshots written by older app builds still decode.
    let ibuprofenSessionEnded: Bool?
    /// True when the parent marked the paracetamol course as skipped/ended.
    let paracetamolSessionEnded: Bool?
    /// When a new ibuprofen dose becomes safe, counting every dose regardless of skip or cycle.
    /// Nil when safe now. Optional so snapshots written by older app builds still decode.
    let ibuprofenBlockedUntil: Date?
    let paracetamolBlockedUntil: Date?
    /// The interval the next dose would use (6 h or 8 h for ibuprofen). Optional for older builds.
    let ibuprofenIntervalHours: Double?
    let paracetamolIntervalHours: Double?
    /// True when the parent-set daily limit is reached, so Lock Screen buttons stay hidden.
    let ibuprofenLimitReached: Bool?
    let paracetamolLimitReached: Bool?

    init(
        childID: String? = nil,
        name: String,
        colorHex: String,
        ibuprofenNextDate: Date?,
        paracetamolNextDate: Date?,
        ibuprofenHasDoses: Bool,
        paracetamolHasDoses: Bool,
        ibuprofenSessionEnded: Bool? = nil,
        paracetamolSessionEnded: Bool? = nil,
        ibuprofenBlockedUntil: Date? = nil,
        paracetamolBlockedUntil: Date? = nil,
        ibuprofenIntervalHours: Double? = nil,
        paracetamolIntervalHours: Double? = nil,
        ibuprofenLimitReached: Bool? = nil,
        paracetamolLimitReached: Bool? = nil
    ) {
        self.childID = childID
        self.name = name
        self.colorHex = colorHex
        self.ibuprofenNextDate = ibuprofenNextDate
        self.paracetamolNextDate = paracetamolNextDate
        self.ibuprofenHasDoses = ibuprofenHasDoses
        self.paracetamolHasDoses = paracetamolHasDoses
        self.ibuprofenSessionEnded = ibuprofenSessionEnded
        self.paracetamolSessionEnded = paracetamolSessionEnded
        self.ibuprofenBlockedUntil = ibuprofenBlockedUntil
        self.paracetamolBlockedUntil = paracetamolBlockedUntil
        self.ibuprofenIntervalHours = ibuprofenIntervalHours
        self.paracetamolIntervalHours = paracetamolIntervalHours
        self.ibuprofenLimitReached = ibuprofenLimitReached
        self.paracetamolLimitReached = paracetamolLimitReached
    }

    func isLimitReached(for medication: Medication) -> Bool {
        switch medication {
        case .ibuprofen:    return ibuprofenLimitReached ?? false
        case .paracetamol:  return paracetamolLimitReached ?? false
        }
    }

    /// Interval for the next dose, falling back to the medication default.
    func intervalHours(for medication: Medication) -> Double {
        let stored: Double?
        switch medication {
        case .ibuprofen:    stored = ibuprofenIntervalHours
        case .paracetamol:  stored = paracetamolIntervalHours
        }
        if let stored, stored > 0 { return stored }
        return medication.intervalHours
    }

    func nextDate(for medication: Medication) -> Date? {
        switch medication {
        case .ibuprofen:    return ibuprofenNextDate
        case .paracetamol:  return paracetamolNextDate
        }
    }

    func hasDoses(for medication: Medication) -> Bool {
        switch medication {
        case .ibuprofen:    return ibuprofenHasDoses
        case .paracetamol:  return paracetamolHasDoses
        }
    }

    func blockedUntil(for medication: Medication) -> Date? {
        switch medication {
        case .ibuprofen:    return ibuprofenBlockedUntil
        case .paracetamol:  return paracetamolBlockedUntil
        }
    }

    func isSessionEnded(for medication: Medication) -> Bool {
        switch medication {
        case .ibuprofen:    return ibuprofenSessionEnded ?? false
        case .paracetamol:  return paracetamolSessionEnded ?? false
        }
    }
}

/// A Lock Screen "Give dose" button that was tapped once and is waiting for the second tap.
struct PendingDoseConfirmation: Codable, Equatable {
    let childID: String
    let medication: String
    let expiresAt: Date

    /// How long the "Tap again to give" state lasts.
    static let window: TimeInterval = 8

    func matches(childID: String, medication: String) -> Bool {
        self.childID == childID && self.medication == medication
    }
}

/// Shared data store between the main app and the widget extension via App Groups.
///
/// Setup required in Xcode:
///   1. Add the "App Groups" capability to the KidDose app, the widget extension, and the watch app.
///   2. Ensure the derived app group `group.<root bundle identifier>` exists in your developer account.
///   3. Add WidgetDataStore.swift to the targets that read or write these snapshots.
enum WidgetDataStore {
    private static let infoPlistKey = "KidDoseAppGroupIdentifier"
    private static let snapshotsKey = "widgetChildSnapshots"

    private static var appGroupID: String? {
        guard
            let configured = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
            !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !configured.contains("$(")
        else {
            assertionFailure("Missing \(infoPlistKey) in \(Bundle.main.bundleIdentifier ?? "unknown bundle").")
            return nil
        }
        return configured
    }

    private static var sharedDefaults: UserDefaults? {
        guard let appGroupID else { return nil }
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            assertionFailure("Unable to open shared defaults for app group \(appGroupID). Check App Groups capabilities for all targets.")
            return nil
        }
        return defaults
    }

    /// Persists the snapshots for the widget extension.
    /// Returns `true` when the stored payload actually changed, so callers can skip
    /// widget reloads (which are budgeted by iOS) and Watch transfers when nothing moved.
    @discardableResult
    static func write(_ snapshots: [WidgetChildSnapshot]) -> Bool {
        guard let defaults = sharedDefaults else { return false }
        guard let data = try? JSONEncoder().encode(snapshots) else { return false }
        if let existing = defaults.data(forKey: snapshotsKey), existing == data {
            return false
        }
        defaults.set(data, forKey: snapshotsKey)
        return true
    }

    private static let pendingConfirmationKey = "widgetPendingDoseConfirmation"

    /// The armed Lock Screen confirmation, or nil when none is armed or it has expired.
    static func readPendingConfirmation(now: Date = .now) -> PendingDoseConfirmation? {
        guard
            let defaults = sharedDefaults,
            let data = defaults.data(forKey: pendingConfirmationKey),
            let pending = try? JSONDecoder().decode(PendingDoseConfirmation.self, from: data),
            pending.expiresAt > now
        else { return nil }
        return pending
    }

    static func writePendingConfirmation(_ pending: PendingDoseConfirmation?) {
        guard let defaults = sharedDefaults else { return }
        if let pending, let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: pendingConfirmationKey)
        } else {
            defaults.removeObject(forKey: pendingConfirmationKey)
        }
    }

    static func read() -> [WidgetChildSnapshot] {
        guard
            let defaults = sharedDefaults,
            let data = defaults.data(forKey: snapshotsKey),
            let snapshots = try? JSONDecoder().decode([WidgetChildSnapshot].self, from: data)
        else { return [] }
        return snapshots
    }
}
