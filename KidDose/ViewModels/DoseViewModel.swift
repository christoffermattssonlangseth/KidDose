import SwiftUI
import SwiftData
import CloudKit
import ActivityKit

// MARK: - Scheduled Dose (upcoming)

/// A future dose window computed from the last logged dose for a child + medication.
struct ScheduledDose: Identifiable {
    let id = UUID()
    let child: Child
    let medication: Medication
    let nextDate: Date
    let intervalHours: Double
}

// MARK: - DoseViewModel

/// Central view model for KidDose, observable by all views.
@MainActor
@Observable
final class DoseViewModel {
    @ObservationIgnored private var lastParticipantShareRefreshAt: Date = .distantPast
    private let participantShareRefreshInterval: TimeInterval = 180

    // MARK: - iCloud Status

    var iCloudAvailable: Bool = true
    var familySyncAvailable: Bool { iCloudAvailable && FamilyCloudSyncService.shared.isConfigured }
    var familySyncEnabled: Bool { FamilyCloudSyncService.shared.isFamilyActive }
    var familySyncOwner: Bool { FamilyCloudSyncService.shared.isFamilyOwner }
    var familyIdentifier: String? { FamilyCloudSyncService.shared.familyIdentifier }
    var familyInviteURL: URL? { FamilyCloudSyncService.shared.inviteURL }
    var familySyncLastStatusMessage: String? { FamilyCloudSyncService.shared.lastSyncStatusMessage }
    var familySyncLastErrorMessage: String? { FamilyCloudSyncService.shared.lastSyncErrorMessage }
    var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "(unknown)" }
    var cloudContainerIdentifier: String { CloudKitConfig.containerIdentifier ?? "(not configured)" }
    var liveActivitiesEnabledOnDevice: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var liveActivityStatusMessage: String { LiveActivityManager.shared.lastStatusMessage }
    var liveActivityErrorMessage: String? { LiveActivityManager.shared.lastErrorMessage }
    var liveActivityLastRefreshAt: Date? { LiveActivityManager.shared.lastRefreshAt }
    var liveActivityLayoutStyle: LiveActivityLayoutStyle = LiveActivityManager.shared.preferredLayoutStyle
    var liveActivityPreferLargeText: Bool = LiveActivityManager.shared.preferLargeText
    var liveActivityDisplayMode: LiveActivityDisplayMode = LiveActivityManager.shared.displayMode
    var liveActivityDueSoonThreshold: LiveActivityDueSoonThreshold = LiveActivityManager.shared.dueSoonThreshold

    func visibleChildrenForCurrentFamily(_ children: [Child]) -> [Child] {
        guard familySyncEnabled, !familySyncOwner else { return children }
        return children.filter { $0.cloudRecordName != nil }
    }

    @MainActor
    func refreshiCloudStatus() async {
        iCloudAvailable = await CloudKitService.shared.checkiCloudStatus()
    }

    @MainActor
    func createSecureFamilyInvite(context: ModelContext) async -> URL? {
        guard familySyncAvailable else { return nil }
        return await FamilyCloudSyncService.shared.createSecureFamily(context: context)
    }

    @MainActor
    func refreshAcceptedFamily(context: ModelContext) async -> Bool {
        guard familySyncAvailable else { return false }
        return await FamilyCloudSyncService.shared.discoverAcceptedFamily(context: context)
    }

    @MainActor
    func acceptCloudShare(
        metadata: CKShare.Metadata,
        context: ModelContext?
    ) async -> Bool {
        await FamilyCloudSyncService.shared.acceptShare(metadata: metadata, context: context)
    }

    @MainActor
    func acceptCloudShareURL(
        _ url: URL,
        context: ModelContext?
    ) async -> Bool {
        await FamilyCloudSyncService.shared.acceptShare(url: url, context: context)
    }

    @MainActor
    func clearFamilySync() {
        FamilyCloudSyncService.shared.clearFamily()
    }

    @MainActor
    func syncFamilyCloud(context: ModelContext, includeUpload: Bool = false) async {
        if familySyncAvailable, !familySyncOwner {
            let shouldRefreshShare =
                !familySyncEnabled
                || Date.now.timeIntervalSince(lastParticipantShareRefreshAt) >= participantShareRefreshInterval
            if shouldRefreshShare {
                lastParticipantShareRefreshAt = .now
                _ = await FamilyCloudSyncService.shared.discoverAcceptedFamily(context: nil)
            }
        } else if !familySyncEnabled, familySyncAvailable {
            _ = await FamilyCloudSyncService.shared.discoverAcceptedFamily(context: nil)
        }

        guard familySyncEnabled else { return }
        if includeUpload {
            await FamilyCloudSyncService.shared.uploadLocalData(context: context)
        }
        await FamilyCloudSyncService.shared.sync(context: context)
        refreshLiveActivity(context: context)
    }

    @MainActor
    func runManualFamilySync(context: ModelContext) async -> Bool {
        guard FamilyCloudSyncService.shared.isConfigured else { return false }

        // Refresh for UI status, but do not hard-stop manual sync on transient account-state checks.
        await refreshiCloudStatus()
        guard familySyncAvailable else {
            FamilyCloudSyncService.shared.noteError(
                iCloudAvailable
                    ? "CloudKit is not configured for this build."
                    : "iCloud is not available. Open Settings → [Your Name] and sign in to iCloud."
            )
            return false
        }

        if !familySyncEnabled {
            _ = await FamilyCloudSyncService.shared.discoverAcceptedFamily(context: nil)
        }

        // Participant devices may keep stale zone pointers after repeated test invites.
        // Re-discover accepted shares before each manual pull.
        if familySyncEnabled, !familySyncOwner {
            _ = await FamilyCloudSyncService.shared.discoverAcceptedFamily(context: nil)
        }

        guard familySyncEnabled else {
            FamilyCloudSyncService.shared.noteError(
                "Family sync is not configured on this device. Create a family or accept an invite above."
            )
            return false
        }
        if familySyncOwner {
            await FamilyCloudSyncService.shared.uploadLocalData(context: context)
        }
        await FamilyCloudSyncService.shared.sync(context: context)
        refreshLiveActivity(context: context)
        return FamilyCloudSyncService.shared.lastSyncErrorMessage == nil
    }

    @MainActor
    func refreshLiveActivity(context: ModelContext) {
        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        LiveActivityManager.shared.refresh(children: children, using: self)
    }

    @MainActor
    func setLiveActivityLayoutStyle(_ style: LiveActivityLayoutStyle, context: ModelContext) {
        liveActivityLayoutStyle = style
        LiveActivityManager.shared.preferredLayoutStyle = style
        refreshLiveActivity(context: context)
    }

    @MainActor
    func setLiveActivityPreferLargeText(_ enabled: Bool, context: ModelContext) {
        liveActivityPreferLargeText = enabled
        LiveActivityManager.shared.preferLargeText = enabled
        refreshLiveActivity(context: context)
    }

    @MainActor
    func setLiveActivityDisplayMode(_ mode: LiveActivityDisplayMode, context: ModelContext) {
        liveActivityDisplayMode = mode
        LiveActivityManager.shared.displayMode = mode
        refreshLiveActivity(context: context)
    }

    @MainActor
    func setLiveActivityDueSoonThreshold(_ threshold: LiveActivityDueSoonThreshold, context: ModelContext) {
        liveActivityDueSoonThreshold = threshold
        LiveActivityManager.shared.dueSoonThreshold = threshold
        refreshLiveActivity(context: context)
    }

    // MARK: - Dose Logic

    func latestDoseInCurrentCycle(for medication: Medication, child: Child) -> DoseLog? {
        dosesInCurrentCycle(for: medication, child: child).first
    }

    /// The absolute next-allowed date based on the latest logged dose and its chosen interval.
    func nextAllowedDate(for medication: Medication, child: Child) -> Date? {
        guard activeSessionEndedAt(for: medication, child: child) == nil else { return nil }
        guard let lastDose = latestDoseInCurrentCycle(for: medication, child: child) else { return nil }
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

    func isMedicationSessionEnded(for medication: Medication, child: Child) -> Bool {
        activeSessionEndedAt(for: medication, child: child) != nil
    }

    func sessionEndedAt(for medication: Medication, child: Child) -> Date? {
        activeSessionEndedAt(for: medication, child: child)
    }

    /// Dose windows across the given children, sorted soonest first.
    /// `clampToNow` keeps overdue windows at "now" for upcoming-only UI surfaces.
    func upcomingDoses(for children: [Child], clampToNow: Bool = true) -> [ScheduledDose] {
        var result: [ScheduledDose] = []
        for child in children {
            for med in Medication.allCases {
                if activeSessionEndedAt(for: med, child: child) != nil { continue }
                guard let lastDose = latestDoseInCurrentCycle(for: med, child: child) else { continue }

                let interval = effectiveInterval(lastDose: lastDose, medication: med)
                let nextAllowed = lastDose.timestamp.addingTimeInterval(interval * 3600)
                let next = clampToNow ? max(nextAllowed, Date.now) : nextAllowed
                result.append(
                    ScheduledDose(
                        child: child,
                        medication: med,
                        nextDate: next,
                        intervalHours: interval
                    )
                )
            }
        }
        return result.sorted { $0.nextDate < $1.nextDate }
    }

    /// Projects the next `dosesPerMedication` dose windows for each medication,
    /// assuming doses are given exactly on-time from now onward.
    func projectedSchedule(
        for child: Child,
        dosesPerMedication: Int = 12,
        from referenceDate: Date = .now
    ) -> [ScheduledDose] {
        guard dosesPerMedication > 0 else { return [] }

        var result: [ScheduledDose] = []
        for med in Medication.allCases {
            if activeSessionEndedAt(for: med, child: child) != nil { continue }
            guard let lastDose = latestDoseInCurrentCycle(for: med, child: child) else { continue }

            let interval = effectiveInterval(lastDose: lastDose, medication: med)
            let nextAllowed = lastDose.timestamp.addingTimeInterval(interval * 3600)
            let firstDate = max(nextAllowed, referenceDate)

            for step in 0..<dosesPerMedication {
                let nextDate = firstDate.addingTimeInterval(Double(step) * interval * 3600)
                result.append(
                    ScheduledDose(
                        child: child,
                        medication: med,
                        nextDate: nextDate,
                        intervalHours: interval
                    )
                )
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
        let previousLatestDose = latestDoseInCurrentCycle(for: medication, child: child)
        if child.sessionEndedAt(for: medication) != nil {
            child.setSessionEndedAt(nil, for: medication)
        }
        if let cycleStartAt = child.cycleStartAt(for: medication), timestamp < cycleStartAt {
            child.setCycleStartAt(timestamp, for: medication)
        }

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
        refreshLiveActivity(context: context)

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
                $0.medication == medication.rawValue
                    && $0.timestamp > timestamp
                    && isDoseInCurrentCycle($0, medication: medication, child: child)
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
        refreshLiveActivity(context: context)
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
            refreshLiveActivity(context: context)
            return
        }

        let wasLatest = latestDoseInCurrentCycle(for: medication, child: child)?
            .persistentModelID == dose.persistentModelID
        let recordName = dose.cloudRecordName

        context.delete(dose)
        try? context.save()
        refreshLiveActivity(context: context)

        if let recordName {
            Task {
                await FamilyCloudSyncService.shared.deleteDoses([recordName])
            }
        }

        guard wasLatest else { return }

        if let newLatestDose = latestDoseInCurrentCycle(for: medication, child: child) {
            if isMedicationSessionEnded(for: medication, child: child) {
                NotificationManager.shared.cancelDoseNotification(
                    childName: child.name,
                    medication: medication
                )
            } else {
                let interval = effectiveInterval(lastDose: newLatestDose, medication: medication)
                scheduleNotification(
                    for: child,
                    medication: medication,
                    intervalHours: interval,
                    from: newLatestDose.timestamp
                )
            }
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
        guard let latestDose = latestDoseInCurrentCycle(for: medication, child: child) else { return }
        latestDose.usedIntervalHours = intervalHours
        try? context.save()
        refreshLiveActivity(context: context)

        Task {
            await FamilyCloudSyncService.shared.upsertDose(latestDose, context: context)
        }

        if isMedicationSessionEnded(for: medication, child: child) {
            NotificationManager.shared.cancelDoseNotification(
                childName: child.name,
                medication: medication
            )
        } else {
            scheduleNotification(
                for: child,
                medication: medication,
                intervalHours: intervalHours,
                from: latestDose.timestamp
            )
        }
    }

    @MainActor
    func endMedicationSession(
        for medication: Medication,
        child: Child,
        context: ModelContext
    ) {
        child.setSessionEndedAt(.now, for: medication)
        try? context.save()
        refreshLiveActivity(context: context)

        NotificationManager.shared.cancelDoseNotification(
            childName: child.name,
            medication: medication
        )

        Task {
            await FamilyCloudSyncService.shared.upsertChild(child, context: context)
        }
    }

    @MainActor
    func restartMedicationSession(
        for medication: Medication,
        child: Child,
        context: ModelContext
    ) {
        child.setSessionEndedAt(nil, for: medication)
        try? context.save()
        refreshLiveActivity(context: context)

        Task {
            await FamilyCloudSyncService.shared.upsertChild(child, context: context)
        }

        if let latestDose = latestDoseInCurrentCycle(for: medication, child: child) {
            let interval = effectiveInterval(lastDose: latestDose, medication: medication)
            scheduleNotification(
                for: child,
                medication: medication,
                intervalHours: interval,
                from: latestDose.timestamp
            )
        } else {
            NotificationManager.shared.cancelDoseNotification(
                childName: child.name,
                medication: medication
            )
        }
    }

    @MainActor
    func startNewInfectionCycle(for child: Child, context: ModelContext) {
        for medication in Medication.allCases {
            child.setSessionEndedAt(nil, for: medication)
            child.setCycleStartAt(.now, for: medication)
            NotificationManager.shared.cancelDoseNotification(
                childName: child.name,
                medication: medication
            )
        }
        try? context.save()
        refreshLiveActivity(context: context)

        Task {
            await FamilyCloudSyncService.shared.upsertChild(child, context: context)
        }
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

    private func activeSessionEndedAt(for medication: Medication, child: Child) -> Date? {
        guard let endedAt = child.sessionEndedAt(for: medication) else { return nil }
        if let cycleStartAt = child.cycleStartAt(for: medication), endedAt < cycleStartAt {
            return nil
        }
        guard let lastDose = latestDoseInCurrentCycle(for: medication, child: child) else { return endedAt }
        return endedAt >= lastDose.timestamp ? endedAt : nil
    }

    private func dosesInCurrentCycle(for medication: Medication, child: Child) -> [DoseLog] {
        let cycleStartAt = child.cycleStartAt(for: medication)
        return child.doses
            .filter { dose in
                guard dose.medication == medication.rawValue else { return false }
                if let cycleStartAt {
                    return dose.timestamp >= cycleStartAt
                }
                return true
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func isDoseInCurrentCycle(_ dose: DoseLog, medication: Medication, child: Child) -> Bool {
        guard dose.medication == medication.rawValue else { return false }
        guard let cycleStartAt = child.cycleStartAt(for: medication) else { return true }
        return dose.timestamp >= cycleStartAt
    }
}
