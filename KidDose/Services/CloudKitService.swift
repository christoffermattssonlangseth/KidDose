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
        static let familyZonePrefix = "KidDoseFamily."
        static let childRecordType = "KidDoseChild"
        static let doseRecordType = "KidDoseDose"
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
        static let zoneNameDefaultsKey = "KidDose.family.zoneName"
        static let zoneOwnerDefaultsKey = "KidDose.family.zoneOwnerName"
        static let roleDefaultsKey = "KidDose.family.role"
        static let inviteURLDefaultsKey = "KidDose.family.inviteURL"
        static let maxQueryPageSize = 400
    }

    private enum FamilyRole: String {
        case owner
        case participant
    }

    private let defaults = UserDefaults.standard
    private let container: CKContainer?
    private(set) var lastSyncStatusMessage: String?
    private(set) var lastSyncErrorMessage: String?

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

    var isFamilyActive: Bool {
        activeZoneID != nil && activeRole != nil
    }

    var isFamilyOwner: Bool {
        activeRole == .owner
    }

    var familyIdentifier: String? {
        activeZoneID?.zoneName
    }

    var inviteURL: URL? {
        guard
            let value = defaults.string(forKey: Constants.inviteURLDefaultsKey),
            let url = URL(string: value)
        else { return nil }
        return url
    }

    func createSecureFamily(context: ModelContext) async -> URL? {
        guard let container else {
            setStatus("Cannot create family because CloudKit is not configured.")
            return nil
        }

        do {
            let privateDB = container.privateCloudDatabase
            let zoneName = Constants.familyZonePrefix + UUID().uuidString
            let zoneID = CKRecordZone.ID(zoneName: zoneName)
            let zone = CKRecordZone(zoneID: zoneID)
            _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])

            let share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = "KidDose Family" as CKRecordValue
            // We share through a private invite URL, so participants can join via the link.
            // `.none` blocks link-based acceptance and surfaces "no access" on recipient devices.
            share.publicPermission = .readWrite
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [])

            setActiveFamily(zoneID: zoneID, role: .owner, inviteURL: share.url)
            lastSyncErrorMessage = nil
            setStatus("Secure family created. Invite another parent using the share link.")

            await uploadLocalData(context: context)
            await sync(context: context)
            return share.url
        } catch {
            setError("Failed to create secure family", error: error)
            return nil
        }
    }

    @discardableResult
    func discoverAcceptedFamily(context: ModelContext? = nil) async -> Bool {
        guard let container else {
            setStatus("Cannot discover shared families because CloudKit is not configured.")
            return false
        }

        do {
            let sharedDB = container.sharedCloudDatabase
            let zoneIDs = try await acceptedFamilyZoneIDs(in: sharedDB)
            guard !zoneIDs.isEmpty else {
                setStatus("No accepted secure family share found on this account.")
                return false
            }

            let selectedZone: CKRecordZone.ID
            if
                activeRole == .participant,
                let currentZoneID = activeZoneID,
                zoneIDs.contains(currentZoneID)
            {
                selectedZone = currentZoneID
            } else {
                selectedZone = await bestParticipantZone(from: zoneIDs, database: sharedDB)
            }

            setActiveFamily(zoneID: selectedZone, role: .participant, inviteURL: nil)
            if zoneIDs.count > 1 {
                setStatus("Connected to secure family share (\(selectedZone.zoneName)).")
            } else {
                setStatus("Connected to secure family share.")
            }
            if let context {
                await sync(context: context)
            }
            return true
        } catch {
            setError("Failed to discover shared family", error: error)
            return false
        }
    }

    @discardableResult
    func acceptShare(metadata: CKShare.Metadata, context: ModelContext? = nil) async -> Bool {
        guard let container else {
            setStatus("Cannot accept share because CloudKit is not configured.")
            return false
        }

        do {
            _ = try await container.accept(metadata)
            let zoneID = metadata.rootRecordID.zoneID
            setActiveFamily(zoneID: zoneID, role: .participant, inviteURL: nil)
            setStatus("Cloud share accepted. Secure family sync is now enabled.")
            if let context {
                await sync(context: context)
            }
            return true
        } catch {
            setError("Failed to accept CloudKit share", error: error)
            return false
        }
    }

    @discardableResult
    func acceptShare(url: URL, context: ModelContext? = nil) async -> Bool {
        guard let container else {
            setStatus("Cannot accept share because CloudKit is not configured.")
            return false
        }

        do {
            let metadata = try await fetchShareMetadata(container: container, url: url)
            return await acceptShare(metadata: metadata, context: context)
        } catch {
            setError("Failed to resolve CloudKit share link", error: error)
            return false
        }
    }

    func clearFamily() {
        defaults.removeObject(forKey: Constants.zoneNameDefaultsKey)
        defaults.removeObject(forKey: Constants.zoneOwnerDefaultsKey)
        defaults.removeObject(forKey: Constants.roleDefaultsKey)
        defaults.removeObject(forKey: Constants.inviteURLDefaultsKey)
        setStatus("Family sync has been disconnected on this device.")
    }

    func uploadLocalData(context: ModelContext) async {
        guard let activeDatabase, activeZoneID != nil else {
            setStatus("Skipped upload because secure family sync is not enabled.")
            return
        }
        lastSyncErrorMessage = nil

        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        for child in children {
            await upsertChild(child, context: context)
        }

        let doses = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        for dose in doses.sorted(by: { $0.timestamp < $1.timestamp }) {
            await upsertDose(dose, context: context)
        }

        _ = activeDatabase
        if lastSyncErrorMessage == nil {
            setStatus("Uploaded \(children.count) children and \(doses.count) doses.")
        } else {
            setStatus("Upload finished with errors.")
        }
    }

    func sync(context: ModelContext) async {
        await sync(context: context, allowParticipantZoneRecovery: true)
    }

    private func sync(context: ModelContext, allowParticipantZoneRecovery: Bool) async {
        guard let db = activeDatabase else {
            lastSyncErrorMessage = "Family sync is not configured for this build."
            setStatus("Sync skipped because CloudKit container is unavailable.")
            return
        }
        guard let zoneID = activeZoneID else {
            setStatus("Sync skipped because secure family sync is not enabled.")
            return
        }
        lastSyncErrorMessage = nil

        do {
            let childRecords = try await fetchRecords(
                recordType: Constants.childRecordType,
                database: db,
                zoneID: zoneID
            )
            let doseRecords = try await fetchRecords(
                recordType: Constants.doseRecordType,
                database: db,
                zoneID: zoneID
            )
            setStatus(
                "Fetched \(childRecords.count) children and \(doseRecords.count) doses from \(zoneID.zoneName)."
            )

            let localChildren = (try? context.fetch(FetchDescriptor<Child>())) ?? []
            var childrenByRecordName: [String: Child] = [:]
            for child in localChildren {
                if let recordName = child.cloudRecordName {
                    childrenByRecordName[recordName] = child
                }
            }
            for record in childRecords {
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

            let sortedDoses = doseRecords.sorted { lhs, rhs in
                let lhsTimestamp = lhs[Constants.timestampField] as? Date ?? .distantPast
                let rhsTimestamp = rhs[Constants.timestampField] as? Date ?? .distantPast
                return lhsTimestamp < rhsTimestamp
            }
            for record in sortedDoses {
                let recordName = record.recordID.recordName
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

                if let existingDose = dosesByRecordName[recordName] {
                    existingDose.medication = medication.rawValue
                    existingDose.timestamp = timestamp
                    existingDose.givenBy = givenBy
                    existingDose.usedIntervalHours = intervalHours
                    if existingDose.child?.cloudRecordName != child.cloudRecordName {
                        existingDose.child = child
                    }
                    continue
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

            do {
                try context.save()
            } catch {
                setError("Local save failed during sync", error: error)
            }
        } catch {
            setError("Sync failed", error: error)
            guard allowParticipantZoneRecovery else { return }
            guard activeRole == .participant else { return }
            guard let currentZoneID = activeZoneID else { return }

            let recovered = await recoverParticipantZone(from: currentZoneID)
            guard recovered else { return }

            await sync(context: context, allowParticipantZoneRecovery: false)
        }
    }

    func upsertChild(_ child: Child, context: ModelContext) async {
        guard let db = activeDatabase, let zoneID = activeZoneID else { return }

        if child.cloudRecordName == nil {
            child.cloudRecordName = UUID().uuidString
            try? context.save()
        }
        guard let recordName = child.cloudRecordName else { return }

        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: Constants.childRecordType, recordID: recordID)
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
            setError("Child upsert failed", error: error)
        }
    }

    func upsertDose(_ dose: DoseLog, context: ModelContext) async {
        guard let db = activeDatabase, let zoneID = activeZoneID, let child = dose.child else { return }

        await upsertChild(child, context: context)

        if dose.cloudRecordName == nil {
            dose.cloudRecordName = UUID().uuidString
            try? context.save()
        }
        guard let recordName = dose.cloudRecordName else { return }

        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: Constants.doseRecordType, recordID: recordID)
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
            setError("Dose upsert failed", error: error)
        }
    }

    func deleteChild(_ child: Child, doseRecordNames: [String]) async {
        guard let db = activeDatabase, let zoneID = activeZoneID else { return }

        var idsToDelete: [CKRecord.ID] = []
        if let childRecordName = child.cloudRecordName {
            idsToDelete.append(CKRecord.ID(recordName: childRecordName, zoneID: zoneID))
        }
        for recordName in doseRecordNames {
            idsToDelete.append(CKRecord.ID(recordName: recordName, zoneID: zoneID))
        }
        guard !idsToDelete.isEmpty else { return }

        do {
            _ = try await db.modifyRecords(
                saving: [],
                deleting: idsToDelete,
                atomically: false
            )
        } catch {
            setError("Delete failed", error: error)
        }
    }

    func deleteDoses(_ doseRecordNames: [String]) async {
        guard let db = activeDatabase, let zoneID = activeZoneID else { return }
        let idsToDelete = doseRecordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        guard !idsToDelete.isEmpty else { return }

        do {
            _ = try await db.modifyRecords(
                saving: [],
                deleting: idsToDelete,
                atomically: false
            )
        } catch {
            setError("Dose delete failed", error: error)
        }
    }

    private func fetchRecords(
        recordType: String,
        database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var firstFailure: Error?
        var changeToken: CKServerChangeToken? = nil
        while true {
            let page = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken,
                resultsLimit: Constants.maxQueryPageSize
            )
            for (_, result) in page.modificationResultsByID {
                switch result {
                case let .success(modification):
                    let record = modification.record
                    guard record.recordType == recordType else { continue }
                    records.append(record)
                case let .failure(error):
                    if firstFailure == nil {
                        firstFailure = error
                    }
                }
            }

            changeToken = page.changeToken
            guard page.moreComing else { break }
        }

        if records.isEmpty, let firstFailure {
            throw firstFailure
        }
        return records
    }

    private func acceptedFamilyZoneIDs(in database: CKDatabase) async throws -> [CKRecordZone.ID] {
        let zones = try await database.allRecordZones()
        return zones
            .map(\.zoneID)
            .filter { $0.zoneName.hasPrefix(Constants.familyZonePrefix) }
            .sorted(by: { $0.zoneName < $1.zoneName })
    }

    private func bestParticipantZone(
        from zoneIDs: [CKRecordZone.ID],
        database: CKDatabase
    ) async -> CKRecordZone.ID {
        guard let first = zoneIDs.first else {
            return CKRecordZone.ID(zoneName: Constants.familyZonePrefix + "unknown")
        }
        guard zoneIDs.count > 1 else { return first }

        var selectedZone = first
        var selectedScore = await zoneDataScore(zoneID: first, database: database)

        for zoneID in zoneIDs.dropFirst() {
            let score = await zoneDataScore(zoneID: zoneID, database: database)
            if score > selectedScore {
                selectedZone = zoneID
                selectedScore = score
                continue
            }

            if score == selectedScore, zoneID.zoneName > selectedZone.zoneName {
                selectedZone = zoneID
            }
        }

        return selectedZone
    }

    private func zoneDataScore(zoneID: CKRecordZone.ID, database: CKDatabase) async -> Int {
        var score = 0
        if let childCount = try? await fetchRecords(
            recordType: Constants.childRecordType,
            database: database,
            zoneID: zoneID
        ).count {
            score += childCount * 1_000
        }

        if let doseCount = try? await fetchRecords(
            recordType: Constants.doseRecordType,
            database: database,
            zoneID: zoneID
        ).count {
            score += doseCount
        }
        return score
    }

    private func recoverParticipantZone(from previousZoneID: CKRecordZone.ID) async -> Bool {
        guard let container else { return false }

        do {
            let sharedDB = container.sharedCloudDatabase
            let zoneIDs = try await acceptedFamilyZoneIDs(in: sharedDB)
            guard !zoneIDs.isEmpty else { return false }

            let candidate = await bestParticipantZone(from: zoneIDs, database: sharedDB)
            guard candidate != previousZoneID else { return false }

            setActiveFamily(zoneID: candidate, role: .participant, inviteURL: nil)
            setStatus("Recovered secure family zone and retried sync.")
            lastSyncErrorMessage = nil
            return true
        } catch {
            return false
        }
    }

    private var activeRole: FamilyRole? {
        guard let raw = defaults.string(forKey: Constants.roleDefaultsKey) else { return nil }
        return FamilyRole(rawValue: raw)
    }

    private var activeZoneID: CKRecordZone.ID? {
        guard
            let zoneName = defaults.string(forKey: Constants.zoneNameDefaultsKey),
            let ownerName = defaults.string(forKey: Constants.zoneOwnerDefaultsKey),
            !zoneName.isEmpty,
            !ownerName.isEmpty
        else {
            return nil
        }
        return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    private var activeDatabase: CKDatabase? {
        guard let container, let role = activeRole else { return nil }
        switch role {
        case .owner:
            return container.privateCloudDatabase
        case .participant:
            return container.sharedCloudDatabase
        }
    }

    private func setActiveFamily(zoneID: CKRecordZone.ID, role: FamilyRole, inviteURL: URL?) {
        defaults.set(zoneID.zoneName, forKey: Constants.zoneNameDefaultsKey)
        defaults.set(zoneID.ownerName, forKey: Constants.zoneOwnerDefaultsKey)
        defaults.set(role.rawValue, forKey: Constants.roleDefaultsKey)
        if let inviteURL {
            defaults.set(inviteURL.absoluteString, forKey: Constants.inviteURLDefaultsKey)
        } else {
            defaults.removeObject(forKey: Constants.inviteURLDefaultsKey)
        }
    }

    private func normalizeNote(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fetchShareMetadata(
        container: CKContainer,
        url: URL
    ) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchShareMetadata(with: url) { metadata, error in
                if let metadata {
                    continuation.resume(returning: metadata)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(
                    throwing: NSError(
                        domain: "KidDose.CloudKit",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Share metadata was unavailable."]
                    )
                )
            }
        }
    }

    private func setStatus(_ message: String) {
        lastSyncStatusMessage = message
        print("[FamilyCloudSync] \(message)")
    }

    private func setError(_ prefix: String, error: Error) {
        let detail = describe(error)
        let message = "\(prefix): \(detail)"
        lastSyncErrorMessage = message
        print("[FamilyCloudSync] \(message)")
    }

    private func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return String(describing: error)
        }

        var parts: [String] = ["CKError.\(ckError.code.rawValue)", ckError.localizedDescription]
        if let retryAfter = ckError.retryAfterSeconds {
            parts.append("retryAfter=\(retryAfter)s")
        }
        if let partialErrors = ckError.partialErrorsByItemID,
           !partialErrors.isEmpty {
            parts.append("partialErrors=\(partialErrors.count)")
        }
        return parts.joined(separator: " | ")
    }
}

extension Notification.Name {
    static let cloudKitDidReceiveRemoteNotification = Notification.Name(
        "cloudKitDidReceiveRemoteNotification"
    )
}
