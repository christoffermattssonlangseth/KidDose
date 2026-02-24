import CloudKit
import SwiftData
import Foundation

enum CloudKitConfig {
    static let placeholderBundleID = "com.yourname.kiddose"
    #if NO_CLOUDKIT
    private static let cloudKitEnabledForBuild = false
    #else
    private static let cloudKitEnabledForBuild = true
    #endif

    /// Uses iCloud.<bundle-id> when the app's bundle id has been configured.
    static var containerIdentifier: String? {
        guard
            cloudKitEnabledForBuild,
            let bundleID = Bundle.main.bundleIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleID.isEmpty,
            bundleID != placeholderBundleID
        else {
            return nil
        }
        return "iCloud.\(bundleID)"
    }

    static var isConfigured: Bool {
        containerIdentifier != nil
    }
}

/// Manages CloudKit subscription setup and handles incoming push payloads.
final class CloudKitService {
    static let shared = CloudKitService()

    private let container: CKContainer?
    private let subscriptionID = "new-dose-log-subscription"

    private init() {
        if let containerIdentifier = CloudKitConfig.containerIdentifier {
            container = CKContainer(identifier: containerIdentifier)
        } else {
            container = nil
        }
    }

    var isConfigured: Bool {
        container != nil
    }

    // MARK: - iCloud Sign-in Status

    @MainActor
    func checkiCloudStatus() async -> Bool {
        guard let container else { return false }
        do {
            let status = try await container.accountStatus()
            guard status == .available else { return false }
            _ = try await container.userRecordID()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Subscription Setup

    /// Creates a CKQuerySubscription that fires on new DoseLog records (called once on launch).
    func setupSubscriptionIfNeeded() async {
        guard let db = container?.privateCloudDatabase else { return }

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
        guard let db = container?.privateCloudDatabase else { return }

        // Attempt to extract metadata from the CKNotification.
        guard
            let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
            let queryNotification = notification as? CKQueryNotification
        else { return }

        let recordID = queryNotification.recordID

        // Fetch the record directly to get givenBy / medication / child name.
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

@MainActor
final class FamilyCloudSyncService {
    static let shared = FamilyCloudSyncService()

    private enum Constants {
        static let childRecordType = "KidDoseChild"
        static let doseRecordType = "KidDoseDose"
        static let familyCodeField = "familyCode"
        static let childNameField = "name"
        static let childColorField = "colorHex"
        static let childIbuprofenDoseNoteField = "ibuprofenDoseNote"
        static let childParacetamolDoseNoteField = "paracetamolDoseNote"
        static let childRecordNameField = "childRecordName"
        static let childFallbackNameField = "childName"
        static let childFallbackColorField = "childColorHex"
        static let medicationField = "medication"
        static let timestampField = "timestamp"
        static let givenByField = "givenBy"
        static let usedIntervalField = "usedIntervalHours"
        static let updatedAtField = "updatedAt"
        static let familyCodeDefaultsKey = "KidDose.familyCode"
        static let maxQueryPageSize = 400
    }

    private let defaults = UserDefaults.standard
    private let database: CKDatabase?

    private init() {
        if let containerIdentifier = CloudKitConfig.containerIdentifier {
            let container = CKContainer(identifier: containerIdentifier)
            database = container.publicCloudDatabase
        } else {
            database = nil
        }
    }

    var isConfigured: Bool {
        database != nil
    }

    var familyCode: String? {
        get {
            normalizeCode(defaults.string(forKey: Constants.familyCodeDefaultsKey))
        }
        set {
            if let normalized = normalizeCode(newValue) {
                defaults.set(normalized, forKey: Constants.familyCodeDefaultsKey)
            } else {
                defaults.removeObject(forKey: Constants.familyCodeDefaultsKey)
            }
        }
    }

    func createFamilyCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<8).compactMap { _ in alphabet.randomElement() })
        familyCode = code
        return code
    }

    func uploadLocalData(context: ModelContext) async {
        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        for child in children {
            await upsertChild(child, context: context)
        }

        let doses = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        for dose in doses.sorted(by: { $0.timestamp < $1.timestamp }) {
            await upsertDose(dose, context: context)
        }
    }

    func sync(context: ModelContext) async {
        guard let db = database, let familyCode else { return }

        do {
            let childRecords = try await fetchAllRecords(
                recordType: Constants.childRecordType,
                database: db
            )
            let doseRecords = try await fetchAllRecords(
                recordType: Constants.doseRecordType,
                database: db
            )

            let filteredChildren = childRecords.filter { record in
                normalizeCode(record[Constants.familyCodeField] as? String) == familyCode
            }
            let filteredDoses = doseRecords.filter { record in
                normalizeCode(record[Constants.familyCodeField] as? String) == familyCode
            }

            let localChildren = (try? context.fetch(FetchDescriptor<Child>())) ?? []
            var childrenByRecordName: [String: Child] = [:]
            for child in localChildren {
                if let recordName = child.cloudRecordName {
                    childrenByRecordName[recordName] = child
                }
            }

            for record in filteredChildren {
                let recordName = record.recordID.recordName
                let name = (record[Constants.childNameField] as? String) ?? "Child"
                let colorHex = (record[Constants.childColorField] as? String) ?? "#4ECDC4"
                let ibuprofenDoseNote = normalizeNote(
                    record[Constants.childIbuprofenDoseNoteField] as? String
                )
                let paracetamolDoseNote = normalizeNote(
                    record[Constants.childParacetamolDoseNoteField] as? String
                )

                if let existing = childrenByRecordName[recordName] {
                    existing.name = name
                    existing.colorHex = colorHex
                    existing.ibuprofenDoseNote = ibuprofenDoseNote
                    existing.paracetamolDoseNote = paracetamolDoseNote
                } else {
                    let child = Child(
                        name: name,
                        colorHex: colorHex,
                        ibuprofenDoseNote: ibuprofenDoseNote,
                        paracetamolDoseNote: paracetamolDoseNote,
                        cloudRecordName: recordName
                    )
                    context.insert(child)
                    childrenByRecordName[recordName] = child
                }
            }

            let localDoses = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
            var dosesByRecordName: [String: DoseLog] = [:]
            for dose in localDoses {
                if let recordName = dose.cloudRecordName {
                    dosesByRecordName[recordName] = dose
                }
            }

            let sortedDoses = filteredDoses.sorted { lhs, rhs in
                let lhsTimestamp = lhs[Constants.timestampField] as? Date ?? .distantPast
                let rhsTimestamp = rhs[Constants.timestampField] as? Date ?? .distantPast
                return lhsTimestamp < rhsTimestamp
            }

            for record in sortedDoses {
                let recordName = record.recordID.recordName
                guard dosesByRecordName[recordName] == nil else { continue }
                guard
                    let medicationRaw = record[Constants.medicationField] as? String,
                    let medication = Medication(rawValue: medicationRaw)
                else {
                    continue
                }

                let childRecordName = record[Constants.childRecordNameField] as? String
                let childName = (record[Constants.childFallbackNameField] as? String) ?? "Child"
                let childColor = (record[Constants.childFallbackColorField] as? String) ?? "#4ECDC4"
                let timestamp = (record[Constants.timestampField] as? Date) ?? .now
                let givenBy = (record[Constants.givenByField] as? String) ?? "Partner"
                let intervalHours = (record[Constants.usedIntervalField] as? Double)
                    ?? medication.intervalHours

                let child: Child
                if
                    let childRecordName,
                    let existingChild = childrenByRecordName[childRecordName]
                {
                    child = existingChild
                } else {
                    let newChild = Child(
                        name: childName,
                        colorHex: childColor,
                        cloudRecordName: childRecordName
                    )
                    context.insert(newChild)
                    if let childRecordName {
                        childrenByRecordName[childRecordName] = newChild
                    }
                    child = newChild
                }

                let dose = DoseLog(
                    medication: medication,
                    intervalHours: intervalHours,
                    timestamp: timestamp,
                    givenBy: givenBy,
                    child: child,
                    cloudRecordName: recordName
                )
                context.insert(dose)
                dosesByRecordName[recordName] = dose
            }

            try? context.save()
        } catch {
            print("[FamilyCloudSync] Sync failed: \(error)")
        }
    }

    func upsertChild(_ child: Child, context: ModelContext) async {
        guard let db = database, let familyCode else { return }

        if child.cloudRecordName == nil {
            child.cloudRecordName = "\(familyCode)_child_\(UUID().uuidString)"
            try? context.save()
        }
        guard let recordName = child.cloudRecordName else { return }

        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: Constants.childRecordType, recordID: recordID)
        record[Constants.familyCodeField] = familyCode as CKRecordValue
        record[Constants.childNameField] = child.name as CKRecordValue
        record[Constants.childColorField] = child.colorHex as CKRecordValue
        record[Constants.childIbuprofenDoseNoteField] =
            (normalizeNote(child.ibuprofenDoseNote) ?? "") as CKRecordValue
        record[Constants.childParacetamolDoseNoteField] =
            (normalizeNote(child.paracetamolDoseNote) ?? "") as CKRecordValue
        record[Constants.updatedAtField] = Date() as CKRecordValue

        do {
            _ = try await db.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
        } catch {
            print("[FamilyCloudSync] Child upsert failed: \(error)")
        }
    }

    func upsertDose(_ dose: DoseLog, context: ModelContext) async {
        guard let db = database, let familyCode, let child = dose.child else { return }

        await upsertChild(child, context: context)

        if dose.cloudRecordName == nil {
            dose.cloudRecordName = "\(familyCode)_dose_\(UUID().uuidString)"
            try? context.save()
        }
        guard let recordName = dose.cloudRecordName else { return }

        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: Constants.doseRecordType, recordID: recordID)
        record[Constants.familyCodeField] = familyCode as CKRecordValue
        record[Constants.childRecordNameField] = (child.cloudRecordName ?? "") as CKRecordValue
        record[Constants.childFallbackNameField] = child.name as CKRecordValue
        record[Constants.childFallbackColorField] = child.colorHex as CKRecordValue
        record[Constants.medicationField] = dose.medication as CKRecordValue
        record[Constants.timestampField] = dose.timestamp as CKRecordValue
        record[Constants.givenByField] = dose.givenBy as CKRecordValue
        record[Constants.usedIntervalField] = dose.usedIntervalHours as CKRecordValue
        record[Constants.updatedAtField] = Date() as CKRecordValue

        do {
            _ = try await db.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
        } catch {
            print("[FamilyCloudSync] Dose upsert failed: \(error)")
        }
    }

    func deleteChild(_ child: Child, doseRecordNames: [String]) async {
        guard let db = database else { return }

        var idsToDelete: [CKRecord.ID] = []
        if let childRecordName = child.cloudRecordName {
            idsToDelete.append(CKRecord.ID(recordName: childRecordName))
        }
        for recordName in doseRecordNames {
            idsToDelete.append(CKRecord.ID(recordName: recordName))
        }
        guard !idsToDelete.isEmpty else { return }

        do {
            _ = try await db.modifyRecords(
                saving: [],
                deleting: idsToDelete,
                atomically: false
            )
        } catch {
            print("[FamilyCloudSync] Delete failed: \(error)")
        }
    }

    func deleteDoses(_ doseRecordNames: [String]) async {
        guard let db = database else { return }
        let idsToDelete = doseRecordNames.map { CKRecord.ID(recordName: $0) }
        guard !idsToDelete.isEmpty else { return }

        do {
            _ = try await db.modifyRecords(
                saving: [],
                deleting: idsToDelete,
                atomically: false
            )
        } catch {
            print("[FamilyCloudSync] Dose delete failed: \(error)")
        }
    }

    private func fetchAllRecords(recordType: String, database: CKDatabase) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var page = try await database.records(
            matching: query,
            resultsLimit: Constants.maxQueryPageSize
        )

        while true {
            for (_, result) in page.matchResults {
                if case let .success(record) = result {
                    records.append(record)
                }
            }

            guard let cursor = page.queryCursor else { break }
            page = try await database.records(
                continuingMatchFrom: cursor,
                resultsLimit: Constants.maxQueryPageSize
            )
        }
        return records
    }

    private func normalizeCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizeNote(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Notification.Name {
    static let cloudKitDidReceiveRemoteNotification = Notification.Name(
        "cloudKitDidReceiveRemoteNotification"
    )
}
