import SwiftUI
import SwiftData

// MARK: - Scheduled Dose (upcoming)

/// A future dose window computed from the last logged dose for a child + medication.
struct ScheduledDose: Identifiable {
    let id = UUID()
    let child: Child
    let medication: Medication
    let nextDate: Date
}

// MARK: - DoseViewModel

/// Central view model for KidDose, observable by all views.
@MainActor
@Observable
final class DoseViewModel {

    // MARK: - iCloud Status

    var iCloudAvailable: Bool = true
    var familyCode: String? { FamilyCloudSyncService.shared.familyCode }
    var familySyncAvailable: Bool { iCloudAvailable && FamilyCloudSyncService.shared.isConfigured }
    var familySyncEnabled: Bool { familyCode != nil }

    @MainActor
    func refreshiCloudStatus() async {
        iCloudAvailable = await CloudKitService.shared.checkiCloudStatus()
    }

    @MainActor
    func createFamilyCode(context: ModelContext) async -> String? {
        guard familySyncAvailable else { return nil }
        let code = FamilyCloudSyncService.shared.createFamilyCode()
        await FamilyCloudSyncService.shared.uploadLocalData(context: context)
        await FamilyCloudSyncService.shared.sync(context: context)
        return code
    }

    @MainActor
    func joinFamily(code: String, context: ModelContext) async -> Bool {
        guard familySyncAvailable else { return false }
        FamilyCloudSyncService.shared.familyCode = code
        await FamilyCloudSyncService.shared.sync(context: context)
        return FamilyCloudSyncService.shared.familyCode != nil
    }

    @MainActor
    func clearFamilyCode() {
        FamilyCloudSyncService.shared.familyCode = nil
    }

    @MainActor
    func syncFamilyCloud(context: ModelContext) async {
        await FamilyCloudSyncService.shared.sync(context: context)
    }

    // MARK: - Dose Logic

    /// Whether a dose of `medication` can be given to `child` right now.
    func canGiveDose(for medication: Medication, child: Child) -> Bool {
        guard let lastDose = child.lastDose(for: medication) else { return true }
        let interval = effectiveInterval(lastDose: lastDose, medication: medication)
        let nextAllowed = lastDose.timestamp.addingTimeInterval(interval * 3600)
        return Date.now >= nextAllowed
    }

    /// The date at which the next dose is allowed, or nil if allowed now.
    func nextDoseDate(for medication: Medication, child: Child) -> Date? {
        guard let lastDose = child.lastDose(for: medication) else { return nil }
        let interval = effectiveInterval(lastDose: lastDose, medication: medication)
        let nextAllowed = lastDose.timestamp.addingTimeInterval(interval * 3600)
        return Date.now < nextAllowed ? nextAllowed : nil
    }

    /// All future dose windows across the given children, sorted soonest first.
    func upcomingDoses(for children: [Child]) -> [ScheduledDose] {
        var result: [ScheduledDose] = []
        for child in children {
            for med in Medication.allCases {
                if let next = nextDoseDate(for: med, child: child) {
                    result.append(ScheduledDose(child: child, medication: med, nextDate: next))
                }
            }
        }
        return result.sorted { $0.nextDate < $1.nextDate }
    }

    // MARK: - Logging

    /// Logs a dose with the specified interval, schedules a notification.
    @MainActor
    func logDose(
        medication: Medication,
        intervalHours: Double,
        for child: Child,
        context: ModelContext
    ) {
        let givenBy = UIDevice.current.name
        let log = DoseLog(
            medication: medication,
            intervalHours: intervalHours,
            givenBy: givenBy,
            child: child
        )
        context.insert(log)
        try? context.save()

        Task {
            await FamilyCloudSyncService.shared.upsertDose(log, context: context)
        }

        scheduleNotification(for: child, medication: medication, intervalHours: intervalHours)
    }

    @MainActor
    func syncChildToFamilyCloud(_ child: Child, context: ModelContext) async {
        await FamilyCloudSyncService.shared.upsertChild(child, context: context)
    }

    @MainActor
    func deleteChild(_ child: Child, context: ModelContext) {
        let doseRecordNames = child.doses.compactMap(\.cloudRecordName)
        Task {
            await FamilyCloudSyncService.shared.deleteChild(child, doseRecordNames: doseRecordNames)
        }

        context.delete(child)
        try? context.save()
    }

    // MARK: - Notifications

    func scheduleNotification(for child: Child, medication: Medication, intervalHours: Double) {
        let nextAllowed = Date.now.addingTimeInterval(intervalHours * 3600)
        NotificationManager.shared.scheduleDoseReady(
            childName: child.name,
            medication: medication,
            nextAllowedAt: nextAllowed
        )
    }

    // MARK: - Stats

    /// Returns a dictionary of [medicationDisplayName: count] for the given children.
    func stats(for children: [Child]) -> [String: Int] {
        var result: [String: Int] = [:]
        for med in Medication.allCases {
            result[med.displayName] = children
                .flatMap(\.doses)
                .filter { $0.medication == med.rawValue }
                .count
        }
        return result
    }

    // MARK: - CloudKit Subscription

    func setupCloudKitSubscription() {
        Task {
            await CloudKitService.shared.setupSubscriptionIfNeeded()
        }
    }

    // MARK: - Private Helpers

    /// Returns the interval to use when computing next-dose time.
    /// Falls back to the medication default for legacy records (usedIntervalHours == 0).
    private func effectiveInterval(lastDose: DoseLog, medication: Medication) -> Double {
        lastDose.usedIntervalHours > 0 ? lastDose.usedIntervalHours : medication.intervalHours
    }
}
