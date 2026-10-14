import SwiftUI
import SwiftData
import CloudKit
import ActivityKit
import WidgetKit

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
    /// Fire dates of the dose-ready notifications last scheduled, keyed by notification ID.
    /// Lets the 15 s sync loop skip rescheduling when nothing changed.
    @ObservationIgnored private var scheduledNotificationPlan: [String: Date]?

    // MARK: - Caregiver

    private static let caregiverNameKey = "KidDose.profile.caregiverName"

    /// The name shown as "Given by". iOS no longer exposes the phone's own name to apps,
    /// so without this every dose would say "iPhone".
    var caregiverName: String = UserDefaults.standard.string(forKey: DoseViewModel.caregiverNameKey) ?? "" {
        didSet {
            UserDefaults.standard.set(
                caregiverName.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Self.caregiverNameKey
            )
        }
    }

    var givenByName: String {
        let trimmed = caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? UIDevice.current.name : trimmed
    }

    // MARK: - Undo

    /// The dose just logged on this device, offered for undo for a few seconds.
    var undoableDose: DoseLog?
    @ObservationIgnored private var undoExpiryTask: Task<Void, Never>?
    /// Course state from just before the undoable dose, so Undo can put it back
    /// (giving a dose resumes a skipped course and can move the course start).
    @ObservationIgnored private var undoPriorSessionEndedAt: Date?
    @ObservationIgnored private var undoPriorCycleStartAt: Date?
    static let undoWindow: Duration = .seconds(10)

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
        // A partner may have deleted the dose the undo banner points at.
        if undoableDose != nil, !hasUndoableDose {
            dismissUndo()
        }
        refreshLiveActivity(context: context)
        // A partner's dose moves the next safe time; keep this device's alert in step.
        await rescheduleAllDoseNotifications(context: context)
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
        await rescheduleAllDoseNotifications(context: context)
        return FamilyCloudSyncService.shared.lastSyncErrorMessage == nil
    }

    /// Refreshes every glanceable surface: Home Screen / Lock Screen widgets, the Watch
    /// snapshots, and the Live Activity. Cheap to call often; widget reloads and Watch
    /// transfers only happen when the snapshot data actually changed.
    @MainActor
    func refreshLiveActivity(context: ModelContext) {
        let children = fetchChildren(context)
        updateWidgetData(children: children)
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

    /// The next dose window shown on cards, widgets and the Live Activity: when both the
    /// interval and the 24 h limit allow another dose. Nil when the course is skipped or
    /// has no doses in the current cycle — use `doseAvailability` for whether Give is safe.
    func nextAllowedDate(for medication: Medication, child: Child) -> Date? {
        guard activeSessionEndedAt(for: medication, child: child) == nil else { return nil }
        guard latestDoseInCurrentCycle(for: medication, child: child) != nil else { return nil }
        return DoseRules.earliestNextDose(
            after: doseRecords(for: medication, child: child),
            maxDosesPer24h: child.maxDailyDoses(for: medication)
        )
    }

    /// Whether a new dose is safe at `date`, counting every logged dose regardless of
    /// infection cycle or "Dose Skipped".
    func doseAvailability(for medication: Medication, child: Child, at date: Date = .now) -> DoseAvailability {
        DoseRules.availability(
            doses: doseRecords(for: medication, child: child),
            maxDosesPer24h: child.maxDailyDoses(for: medication),
            at: date
        )
    }

    /// Whether a dose of `medication` can be given to `child` right now.
    func canGiveDose(for medication: Medication, child: Child) -> Bool {
        doseAvailability(for: medication, child: child).isAllowed
    }

    /// The date at which the next dose is allowed, or nil if allowed now.
    func nextDoseDate(for medication: Medication, child: Child) -> Date? {
        doseAvailability(for: medication, child: child).blockedUntil
    }

    func dosesInLast24h(for medication: Medication, child: Child) -> Int {
        DoseRules.dosesInLast24h(doseRecords(for: medication, child: child), at: .now)
    }

    /// Rules a past dose at `timestamp` would break. When `replacingNewer` is on, the newer
    /// doses that would be deleted are left out of the check.
    func pastDoseConflicts(
        medication: Medication,
        intervalHours: Double,
        timestamp: Date,
        replacingNewer: Bool,
        child: Child
    ) -> [DoseConflict] {
        let removed = replacingNewer
            ? Set(newerDosesInCurrentCycle(than: timestamp, medication: medication, child: child).map(\.persistentModelID))
            : []
        return DoseRules.conflicts(
            adding: DoseRecord(timestamp: timestamp, intervalHours: intervalHours),
            to: doseRecords(for: medication, child: child, excluding: removed),
            maxDosesPer24h: child.maxDailyDoses(for: medication)
        )
    }

    func newerDosesInCurrentCycle(than timestamp: Date, medication: Medication, child: Child) -> [DoseLog] {
        child.doses.filter {
            $0.medication == medication.rawValue
                && $0.timestamp > timestamp
                && isDoseInCurrentCycle($0, medication: medication, child: child)
        }
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
                guard
                    let lastDose = latestDoseInCurrentCycle(for: med, child: child),
                    let nextAllowed = nextAllowedDate(for: med, child: child)
                else { continue }

                let interval = effectiveInterval(lastDose: lastDose, medication: med)
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
            let limit = child.maxDailyDoses(for: med)
            // Simulate on-time doses so the projection respects the 24 h limit too.
            var simulated = doseRecords(for: med, child: child)

            for _ in 0..<dosesPerMedication {
                guard let earliest = DoseRules.earliestNextDose(after: simulated, maxDosesPer24h: limit) else { break }
                let nextDate = max(earliest, referenceDate)
                simulated.append(DoseRecord(timestamp: nextDate, intervalHours: interval))
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
        let priorSessionEndedAt = child.sessionEndedAt(for: medication)
        let priorCycleStartAt = child.cycleStartAt(for: medication)
        if child.sessionEndedAt(for: medication) != nil {
            child.setSessionEndedAt(nil, for: medication)
        }
        if let cycleStartAt = child.cycleStartAt(for: medication), timestamp < cycleStartAt {
            child.setCycleStartAt(timestamp, for: medication)
        }

        let log = DoseLog(
            medication: medication,
            intervalHours: intervalHours,
            timestamp: timestamp,
            givenBy: givenByName,
            child: child,
            amount: child.doseNote(for: medication)
        )
        context.insert(log)
        saveContext(context)
        refreshLiveActivity(context: context)
        offerUndo(for: log, priorSessionEndedAt: priorSessionEndedAt, priorCycleStartAt: priorCycleStartAt)

        Task {
            await FamilyCloudSyncService.shared.upsertDose(log, context: context)
        }

        updateDoseNotification(for: medication, child: child)
    }

    /// Records a dose requested from the Apple Watch. The dose has already been given, so it
    /// is always logged; if it breaks a rule the parent gets a warning on the iPhone.
    @MainActor
    func logWatchDose(
        medication: Medication,
        intervalHours: Double,
        timestamp: Date,
        for child: Child,
        context: ModelContext
    ) {
        let conflicts = DoseRules.conflicts(
            adding: DoseRecord(timestamp: timestamp, intervalHours: intervalHours),
            to: doseRecords(for: medication, child: child),
            maxDosesPer24h: child.maxDailyDoses(for: medication)
        )
        logDose(
            medication: medication,
            intervalHours: intervalHours,
            timestamp: timestamp,
            for: child,
            context: context
        )
        guard !conflicts.isEmpty else { return }
        NotificationManager.shared.postDoseWarning(
            title: "Check \(child.name)'s \(medication.displayName.lowercased()) dose",
            body: "Logged from Apple Watch at \(timestamp.formatted(date: .omitted, time: .shortened)). "
                + conflicts.map { $0.explanation(medicationName: medication.displayName) }.joined(separator: " ")
        )
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
            let newerDoses = newerDosesInCurrentCycle(than: timestamp, medication: medication, child: child)
            let recordNames = newerDoses.compactMap(\.cloudRecordName)

            for dose in newerDoses {
                if undoableDose === dose {
                    dismissUndo()
                }
                context.delete(dose)
            }
            saveContext(context)

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
        // Read everything needed for the cloud delete now; the model is gone once saved.
        let childRecordName = child.cloudRecordName
        let relatedRecordNames = child.doses.compactMap(\.cloudRecordName)
            + child.temperatureReadings.compactMap(\.cloudRecordName)
        Task {
            await FamilyCloudSyncService.shared.deleteChild(
                recordName: childRecordName,
                relatedRecordNames: relatedRecordNames
            )
        }
        // Pending "dose ready" alerts would otherwise still fire for a deleted child.
        for medication in Medication.allCases {
            cancelNotification(for: child, medication: medication)
        }
        if undoableDose?.child?.persistentModelID == child.persistentModelID {
            undoableDose = nil
        }

        context.delete(child)
        saveContext(context)
        refreshLiveActivity(context: context)
    }

    @MainActor
    func deleteDose(_ dose: DoseLog, context: ModelContext) {
        if undoableDose === dose {
            dismissUndo()
        }
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
            saveContext(context)
            refreshLiveActivity(context: context)
            return
        }

        let recordName = dose.cloudRecordName

        context.delete(dose)
        saveContext(context)
        refreshLiveActivity(context: context)

        if let recordName {
            Task {
                await FamilyCloudSyncService.shared.deleteDoses([recordName])
            }
        }

        // Any deleted dose can move the 24 h limit, not just the latest one.
        updateDoseNotification(for: medication, child: child)
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
        saveContext(context)
        refreshLiveActivity(context: context)

        Task {
            await FamilyCloudSyncService.shared.upsertDose(latestDose, context: context)
        }

        updateDoseNotification(for: medication, child: child)
    }

    @MainActor
    func endMedicationSession(
        for medication: Medication,
        child: Child,
        context: ModelContext
    ) {
        child.setSessionEndedAt(.now, for: medication)
        saveContext(context)
        refreshLiveActivity(context: context)
        updateDoseNotification(for: medication, child: child)

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
        saveContext(context)
        refreshLiveActivity(context: context)

        Task {
            await FamilyCloudSyncService.shared.upsertChild(child, context: context)
        }

        updateDoseNotification(for: medication, child: child)
    }

    @MainActor
    func startNewInfectionCycle(for child: Child, context: ModelContext) {
        for medication in Medication.allCases {
            child.setSessionEndedAt(nil, for: medication)
            child.setCycleStartAt(.now, for: medication)
        }
        saveContext(context)
        refreshLiveActivity(context: context)
        for medication in Medication.allCases {
            updateDoseNotification(for: medication, child: child)
        }

        Task {
            await FamilyCloudSyncService.shared.upsertChild(child, context: context)
        }
    }

    // MARK: - Undo

    private func offerUndo(for dose: DoseLog, priorSessionEndedAt: Date?, priorCycleStartAt: Date?) {
        // Only doses logged "now" on this device; past doses come from a deliberate sheet.
        guard abs(dose.timestamp.timeIntervalSinceNow) < 120 else { return }
        undoableDose = dose
        undoPriorSessionEndedAt = priorSessionEndedAt
        undoPriorCycleStartAt = priorCycleStartAt
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            if self?.undoableDose === dose {
                self?.undoableDose = nil
            }
        }
    }

    func dismissUndo() {
        undoExpiryTask?.cancel()
        undoableDose = nil
        undoPriorSessionEndedAt = nil
        undoPriorCycleStartAt = nil
    }

    /// True while the undo banner's dose is still a live record.
    var hasUndoableDose: Bool {
        guard let dose = undoableDose else { return false }
        return !dose.isDeleted && dose.modelContext != nil
    }

    @MainActor
    func undoLastDose(context: ModelContext) {
        guard let dose = undoableDose, hasUndoableDose else {
            dismissUndo()
            return
        }
        let priorSessionEndedAt = undoPriorSessionEndedAt
        let priorCycleStartAt = undoPriorCycleStartAt
        dismissUndo()

        // Put the course back the way it was before the dose (e.g. still "Skipped") before
        // deleting, so deleteDose reschedules or cancels alerts against the restored state.
        if let child = dose.child, let medication = dose.medicationEnum {
            child.setSessionEndedAt(priorSessionEndedAt, for: medication)
            child.setCycleStartAt(priorCycleStartAt, for: medication)
            Task {
                await FamilyCloudSyncService.shared.upsertChild(child, context: context)
            }
        }
        deleteDose(dose, context: context)
    }

    // MARK: - Daily Limits

    /// Doses of `medication` given in the 24 hours up to `date`.
    func dosesInLast24Hours(for medication: Medication, child: Child, at date: Date = .now) -> Int {
        let timestamps = child.doses
            .filter { $0.medication == medication.rawValue }
            .map(\.timestamp)
        return DoseRules.timestampsInWindow(timestamps, endingAt: date).count
    }

    /// Nil when the parent hasn't set a limit for this child and medication.
    func dailyLimitStatus(for medication: Medication, child: Child, at date: Date = .now) -> DailyLimitStatus? {
        guard let limit = child.maxDailyDoses(for: medication), limit > 0 else { return nil }
        let timestamps = child.doses
            .filter { $0.medication == medication.rawValue }
            .map(\.timestamp)
        return DailyLimitStatus(
            given: DoseRules.timestampsInWindow(timestamps, endingAt: date).count,
            limit: limit,
            resetsAt: DoseRules.limitResetDate(timestamps: timestamps, limit: limit, at: date)
        )
    }

    @MainActor
    func setMaxDailyDoses(_ value: Int?, for medication: Medication, child: Child, context: ModelContext) {
        child.setMaxDailyDoses(value, for: medication)
        saveContext(context)
        Task {
            await FamilyCloudSyncService.shared.upsertChild(child, context: context)
        }
    }

    // MARK: - Dose Amount

    @MainActor
    func setAmount(_ amount: String?, for dose: DoseLog, context: ModelContext) {
        let trimmed = amount?.trimmingCharacters(in: .whitespacesAndNewlines)
        dose.amount = (trimmed?.isEmpty ?? true) ? nil : trimmed
        saveContext(context)
        Task {
            await FamilyCloudSyncService.shared.upsertDose(dose, context: context)
        }
    }

    // MARK: - Temperature

    @MainActor
    func addReading(
        celsius: Double?,
        symptoms: String?,
        timestamp: Date = .now,
        for child: Child,
        context: ModelContext
    ) {
        let reading = TemperatureLog(
            timestamp: timestamp,
            celsius: celsius,
            symptoms: symptoms,
            recordedBy: givenByName,
            child: child
        )
        context.insert(reading)
        saveContext(context)
        Task {
            await FamilyCloudSyncService.shared.upsertReading(reading, context: context)
        }
    }

    @MainActor
    func deleteReading(_ reading: TemperatureLog, context: ModelContext) {
        let recordName = reading.cloudRecordName
        context.delete(reading)
        saveContext(context)
        if let recordName {
            Task {
                await FamilyCloudSyncService.shared.deleteDoses([recordName])
            }
        }
    }

    // MARK: - Stored Data Upkeep

    /// Run once at launch: gives older children a stable ID so alerts and the Watch stop
    /// depending on names.
    @MainActor
    func prepareStoredData(context: ModelContext) {
        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        var changed = false
        for child in children where child.uid == nil {
            child.uid = UUID().uuidString
            changed = true
        }
        if changed {
            saveContext(context)
        }
    }

    /// The interval the next dose would use: the latest dose's choice, else the default.
    func currentInterval(for medication: Medication, child: Child) -> Double {
        let latest = latestDoseInCurrentCycle(for: medication, child: child) ?? child.lastDose(for: medication)
        if let latest, latest.usedIntervalHours > 0 { return latest.usedIntervalHours }
        return medication.intervalHours
    }

    // MARK: - Notifications

    /// Rebuilds every pending dose-ready notification from current state.
    /// Wipes orphans first so renamed children or stale intervals can't keep firing.
    /// Skips the work when the planned alerts match what was last scheduled.
    @MainActor
    func rescheduleAllDoseNotifications(context: ModelContext) async {
        let children = fetchChildren(context)
        var plan: [String: Date] = [:]
        for child in children {
            for medication in Medication.allCases {
                if let fireDate = notificationFireDate(for: medication, child: child) {
                    plan[child.notificationID(for: medication)] = fireDate
                }
            }
        }
        guard plan != scheduledNotificationPlan else { return }

        await NotificationManager.shared.cancelAllPendingDoseNotifications()
        for child in children {
            for medication in Medication.allCases {
                updateDoseNotification(for: medication, child: child)
            }
        }
        scheduledNotificationPlan = plan
    }

    /// Schedules (or cancels) the dose-ready alert for one child + medication from current state.
    func updateDoseNotification(for medication: Medication, child: Child) {
        guard
            let fireDate = notificationFireDate(for: medication, child: child),
            let lastDose = latestDoseInCurrentCycle(for: medication, child: child)
        else {
            cancelNotification(for: child, medication: medication)
            return
        }

        let interval = effectiveInterval(lastDose: lastDose, medication: medication)
        let limitIsReason = lastDose.timestamp.addingTimeInterval(interval * 3600) < fireDate
        NotificationManager.shared.scheduleDoseReady(
            childID: child.stableID,
            childName: child.name,
            medication: medication,
            body: limitIsReason
                ? "The 24-hour dose limit has cleared — you can give the next dose."
                : "It's been \(Int(interval)) hours — you can give the next dose.",
            nextAllowedAt: fireDate
        )
    }

    private func notificationFireDate(for medication: Medication, child: Child) -> Date? {
        guard let next = nextAllowedDate(for: medication, child: child), next > .now else { return nil }
        return next
    }

    // MARK: - Dose Limits

    @MainActor
    func setDoseInstructions(note: String?, maxDailyDoses: Int?, for medication: Medication, child: Child, context: ModelContext) {
        child.setDoseNote(note, for: medication)
        child.setMaxDailyDoses(maxDailyDoses, for: medication)
        saveContext(context)
        refreshLiveActivity(context: context)
        updateDoseNotification(for: medication, child: child)

        Task {
            await FamilyCloudSyncService.shared.upsertChild(child, context: context)
        }
    }

    func cancelNotification(for child: Child, medication: Medication) {
        NotificationManager.shared.cancelDoseNotification(
            childID: child.stableID,
            childName: child.name,
            medication: medication
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

    // MARK: - Widget Data

    /// Pushes the current snapshots to the Watch even if nothing changed (used at launch,
    /// when the Watch may have missed earlier transfers).
    func sendSnapshotsToWatch(context: ModelContext) {
        let children = fetchChildren(context)
        updateWidgetData(children: children, forceDelivery: true)
    }

    private func updateWidgetData(children: [Child], forceDelivery: Bool = false) {
        let snapshots = children.map { child in
            WidgetChildSnapshot(
                childID: child.uid,
                name: child.name,
                colorHex: child.colorHex,
                ibuprofenNextDate: nextAllowedDate(for: .ibuprofen, child: child),
                paracetamolNextDate: nextAllowedDate(for: .paracetamol, child: child),
                ibuprofenHasDoses: latestDoseInCurrentCycle(for: .ibuprofen, child: child) != nil,
                paracetamolHasDoses: latestDoseInCurrentCycle(for: .paracetamol, child: child) != nil,
                ibuprofenSessionEnded: isMedicationSessionEnded(for: .ibuprofen, child: child),
                paracetamolSessionEnded: isMedicationSessionEnded(for: .paracetamol, child: child),
                ibuprofenBlockedUntil: doseAvailability(for: .ibuprofen, child: child).blockedUntil,
                paracetamolBlockedUntil: doseAvailability(for: .paracetamol, child: child).blockedUntil,
                ibuprofenIntervalHours: currentInterval(for: .ibuprofen, child: child),
                paracetamolIntervalHours: currentInterval(for: .paracetamol, child: child),
                ibuprofenLimitReached: dailyLimitStatus(for: .ibuprofen, child: child)?.isReached ?? false,
                paracetamolLimitReached: dailyLimitStatus(for: .paracetamol, child: child)?.isReached ?? false
            )
        }
        let changed = WidgetDataStore.write(snapshots)
        guard changed || forceDelivery else { return }
        PhoneSessionManager.shared.sendSnapshots(snapshots)
        WidgetCenter.shared.reloadTimelines(ofKind: "KidDoseHomeWidget")
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

    /// Every logged dose of `medication`, across all cycles — the input to `DoseRules`.
    private func doseRecords(
        for medication: Medication,
        child: Child,
        excluding excluded: Set<PersistentIdentifier> = []
    ) -> [DoseRecord] {
        child.doses
            .filter { $0.medication == medication.rawValue && !excluded.contains($0.persistentModelID) }
            .map { DoseRecord(timestamp: $0.timestamp, intervalHours: effectiveInterval(lastDose: $0, medication: medication)) }
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

    private func saveContext(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            print("[DoseViewModel] Failed to save context: \(error)")
        }
    }

    private func fetchChildren(_ context: ModelContext, caller: StaticString = #function) -> [Child] {
        do {
            return try context.fetch(FetchDescriptor<Child>())
        } catch {
            print("[DoseViewModel] Child fetch failed in \(caller): \(error)")
            return []
        }
    }

    private func isDoseInCurrentCycle(_ dose: DoseLog, medication: Medication, child: Child) -> Bool {
        guard dose.medication == medication.rawValue else { return false }
        guard let cycleStartAt = child.cycleStartAt(for: medication) else { return true }
        return dose.timestamp >= cycleStartAt
    }
}
