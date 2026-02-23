import CloudKit
import SwiftData
import Foundation

/// Manages CloudKit subscription setup and handles incoming push payloads.
final class CloudKitService {
    static let shared = CloudKitService()

    private let container = CKContainer(identifier: "iCloud.com.yourname.kiddose")
    private let subscriptionID = "new-dose-log-subscription"

    private init() {}

    // MARK: - iCloud Sign-in Status

    @MainActor
    func checkiCloudStatus() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    // MARK: - Subscription Setup

    /// Creates a CKQuerySubscription that fires on new DoseLog records (called once on launch).
    func setupSubscriptionIfNeeded() async {
        let db = container.privateCloudDatabase

        // Check if subscription already exists.
        do {
            let existingSubs = try await db.allSubscriptions()
            if existingSubs.contains(where: { $0.subscriptionID == subscriptionID }) {
                return
            }
        } catch {
            // Ignore — attempt to create anyway.
        }

        let predicate = NSPredicate(value: true)
        let subscription = CKQuerySubscription(
            recordType: "CD_DoseLog",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: .firesOnRecordCreation
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // silent push
        subscription.notificationInfo = notificationInfo

        do {
            try await db.save(subscription)
        } catch {
            print("[CloudKitService] Failed to save subscription: \(error)")
        }
    }

    // MARK: - Handle Incoming Push

    /// Called from AppDelegate when a silent push arrives.
    /// Fetches the most recent DoseLog record created on another device and fires a local notification.
    func handleRemoteNotification(
        userInfo: [AnyHashable: Any],
        modelContext: ModelContext
    ) async {
        // Trigger a background context save/refresh so SwiftData re-fetches.
        // SwiftData with NSPersistentCloudKitContainer handles merging automatically;
        // we just need to post a notification so views refresh.
        NotificationCenter.default.post(name: .cloudKitDidReceiveRemoteNotification, object: nil)

        // Attempt to extract metadata from the CKNotification.
        guard
            let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
            let queryNotification = notification as? CKQueryNotification
        else { return }

        let recordID = queryNotification.recordID

        // Fetch the record directly to get givenBy / medication / child name.
        let db = container.privateCloudDatabase
        do {
            guard let recordID = recordID else { return }
            let record = try await db.record(for: recordID)

            let medication = record["CD_medication"] as? String ?? "medication"
            let givenBy    = record["CD_givenBy"]    as? String ?? "Partner"
            let childName  = (record["CD_child"] as? CKRecord.Reference).map { _ in "" } ?? ""
            let timestamp  = record["CD_timestamp"]  as? Date   ?? .now

            // Fire a local notification (regular priority — not critical).
            await MainActor.run {
                NotificationManager.shared.schedulePartnerDoseNotification(
                    partner: givenBy,
                    medication: medication,
                    childName: childName.isEmpty ? "your child" : childName,
                    at: timestamp
                )
            }
        } catch {
            // Record may not exist yet; SwiftData sync will handle it shortly.
            print("[CloudKitService] Could not fetch record: \(error)")
        }
    }
}

extension Notification.Name {
    static let cloudKitDidReceiveRemoteNotification = Notification.Name(
        "cloudKitDidReceiveRemoteNotification"
    )
}
