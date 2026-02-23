import SwiftUI
import SwiftData

/// Central view model for KidDose, observable by all views.
@Observable
final class DoseViewModel {

    // MARK: - iCloud Status

    var iCloudAvailable: Bool = true

    // MARK: - iCloud Status Check

    @MainActor
    func refreshiCloudStatus() async {
        iCloudAvailable = await CloudKitService.shared.checkiCloudStatus()
    }

    // MARK: - Dose Logic

    /// Whether a dose of `medication` can be given to `child` right now.
    func canGiveDose(for medication: Medication, child: Child) -> Bool {
        guard let lastDose = child.lastDose(for: medication) else { return true }
        let nextAllowed = lastDose.timestamp.addingTimeInterval(medication.intervalHours * 3600)
        return Date.now >= nextAllowed
    }

    /// The date at which the next dose is allowed, or nil if allowed now.
    func nextDoseDate(for medication: Medication, child: Child) -> Date? {
        guard let lastDose = child.lastDose(for: medication) else { return nil }
        let nextAllowed = lastDose.timestamp.addingTimeInterval(medication.intervalHours * 3600)
        return Date.now < nextAllowed ? nextAllowed : nil
    }

    // MARK: - Logging

    /// Logs a dose, schedules a notification, and triggers haptic feedback.
    @MainActor
    func logDose(
        medication: Medication,
        for child: Child,
        context: ModelContext
    ) {
        let givenBy = UIDevice.current.name
        let log = DoseLog(medication: medication, givenBy: givenBy, child: child)
        context.insert(log)
        try? context.save()

        // Schedule a Critical Alert for when next dose is allowed.
        scheduleNotification(for: child, medication: medication)
    }

    // MARK: - Notifications

    func scheduleNotification(for child: Child, medication: Medication) {
        let nextAllowed = Date.now.addingTimeInterval(medication.intervalHours * 3600)
        NotificationManager.shared.scheduleDoseReady(
            childName: child.name,
            medication: medication,
            nextAllowedAt: nextAllowed
        )
    }

    // MARK: - Stats

    /// Returns a dictionary of [medicationDisplayName: count] for the given child filter.
    func stats(for children: [Child]?) -> [String: Int] {
        var result: [String: Int] = [:]
        for med in Medication.allCases {
            let count: Int
            if let children = children {
                count = children.flatMap(\.doses).filter { $0.medication == med.rawValue }.count
            } else {
                count = 0
            }
            result[med.displayName] = count
        }
        return result
    }

    // MARK: - CloudKit Subscription

    func setupCloudKitSubscription() {
        Task {
            await CloudKitService.shared.setupSubscriptionIfNeeded()
        }
    }
}
