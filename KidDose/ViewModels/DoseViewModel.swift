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

    /// The absolute next-allowed date based on the latest logged dose and its chosen interval.
    func nextAllowedDate(for medication: Medication, child: Child) -> Date? {
        guard let lastDose = child.lastDose(for: medication) else { return nil }
        let interval = effectiveInterval(lastDose: lastDose, medication: medication)
        return lastDose.timestamp.addingTimeInterval(interval * 3600)
    }

    /// Whether a dose of `medication` can be given to `child` right now.
    func canGiveDose(for medication: Medication, child: Child) -> Bool {
        guard let nextAllowed = nextAllowedDate(for: medication, child: child) else { return true }
        return Date.now >= nextAllowed
    }

    /// The date at which the next dose is allowed, or nil if allowed now.
    func nextDoseDate(for medication: Medication, child: Child) -> Date? {
        guard let nextAllowed = nextAllowedDate(for: medication, child: child) else { return nil }
        return Date.now < nextAllowed ? nextAllowed : nil
    }

    /// How long the dose has been overdue (if overdue), otherwise nil.
    func overdueDuration(
        for medication: Medication,
        child: Child,
        relativeTo date: Date = .now
    ) -> TimeInterval? {
        guard let nextAllowed = nextAllowedDate(for: medication, child: child) else { return nil }
        let overdue = date.timeIntervalSince(nextAllowed)
        return overdue > 0 ? overdue : nil
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
        timestamp: Date = .now,
        for child: Child,
        context: ModelContext
    ) {
        let previousLatestDose = child.lastDose(for: medication)

        let givenBy = UIDevice.current.name
        let log = DoseLog(
            medication: medication,
            intervalHours: intervalHours,
            timestamp: timestamp,
            givenBy: givenBy,
            child: child
        )
        context.insert(log)
        try? context.save()

        Task {
            await FamilyCloudSyncService.shared.upsertDose(log, context: context)
        }

        let shouldUpdateNotification: Bool
        if let previousLatestDose {
            shouldUpdateNotification = timestamp >= previousLatestDose.timestamp
        } else {
            shouldUpdateNotification = true
        }

        if shouldUpdateNotification {
            scheduleNotification(
                for: child,
                medication: medication,
                intervalHours: intervalHours,
                from: timestamp
            )
        }
    }

    @MainActor
    func logRetroactiveDose(
        medication: Medication,
        intervalHours: Double,
        timestamp: Date,
        setAsLatest: Bool,
        for child: Child,
        context: ModelContext
    ) {
        if setAsLatest {
            let newerDoses = child.doses.filter {
                $0.medication == medication.rawValue && $0.timestamp > timestamp
            }
            let recordNames = newerDoses.compactMap(\.cloudRecordName)

            for dose in newerDoses {
                context.delete(dose)
            }
            try? context.save()

            if !recordNames.isEmpty {
                Task {
                    await FamilyCloudSyncService.shared.deleteDoses(recordNames)
                }
            }
        }

        logDose(
            medication: medication,
            intervalHours: intervalHours,
            timestamp: timestamp,
            for: child,
            context: context
        )
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

    @MainActor
    func deleteDose(_ dose: DoseLog, context: ModelContext) {
        guard
            let child = dose.child,
            let medication = dose.medicationEnum
        else {
            if let recordName = dose.cloudRecordName {
                Task {
                    await FamilyCloudSyncService.shared.deleteDoses([recordName])
                }
            }
            context.delete(dose)
            try? context.save()
            return
        }

        let wasLatest = child.lastDose(for: medication)?.persistentModelID == dose.persistentModelID
        let recordName = dose.cloudRecordName

        context.delete(dose)
        try? context.save()

        if let recordName {
            Task {
                await FamilyCloudSyncService.shared.deleteDoses([recordName])
            }
        }

        guard wasLatest else { return }

        if let newLatestDose = child.lastDose(for: medication) {
            let interval = effectiveInterval(lastDose: newLatestDose, medication: medication)
            scheduleNotification(
                for: child,
                medication: medication,
                intervalHours: interval,
                from: newLatestDose.timestamp
            )
        } else {
            NotificationManager.shared.cancelDoseNotification(
                childName: child.name,
                medication: medication
            )
        }
    }

    @MainActor
    func setLatestDoseInterval(
        for medication: Medication,
        intervalHours: Double,
        child: Child,
        context: ModelContext
    ) {
        guard let latestDose = child.lastDose(for: medication) else { return }
        latestDose.usedIntervalHours = intervalHours
        try? context.save()

        Task {
            await FamilyCloudSyncService.shared.upsertDose(latestDose, context: context)
        }

        scheduleNotification(
            for: child,
            medication: medication,
            intervalHours: intervalHours,
            from: latestDose.timestamp
        )
    }

    // MARK: - Notifications

    func scheduleNotification(
        for child: Child,
        medication: Medication,
        intervalHours: Double,
        from timestamp: Date = .now
    ) {
        let nextAllowed = timestamp.addingTimeInterval(intervalHours * 3600)
        NotificationManager.shared.scheduleDoseReady(
            childName: child.name,
            medication: medication,
            intervalHours: intervalHours,
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
        guard iCloudAvailable else { return }
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
