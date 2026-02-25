import SwiftData
import Foundation

@Model
final class Child {
    var name: String
    var colorHex: String
    var cloudRecordName: String?
    var ibuprofenDoseNote: String?
    var paracetamolDoseNote: String?
    var ibuprofenSessionEndedAt: Date?
    var paracetamolSessionEndedAt: Date?
    var ibuprofenCycleStartAt: Date?
    var paracetamolCycleStartAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \DoseLog.child)
    var doses: [DoseLog] = []

    init(
        name: String,
        colorHex: String,
        ibuprofenDoseNote: String? = nil,
        paracetamolDoseNote: String? = nil,
        ibuprofenSessionEndedAt: Date? = nil,
        paracetamolSessionEndedAt: Date? = nil,
        ibuprofenCycleStartAt: Date? = nil,
        paracetamolCycleStartAt: Date? = nil,
        cloudRecordName: String? = nil
    ) {
        self.name = name
        self.colorHex = colorHex
        self.ibuprofenDoseNote = ibuprofenDoseNote
        self.paracetamolDoseNote = paracetamolDoseNote
        self.ibuprofenSessionEndedAt = ibuprofenSessionEndedAt
        self.paracetamolSessionEndedAt = paracetamolSessionEndedAt
        self.ibuprofenCycleStartAt = ibuprofenCycleStartAt
        self.paracetamolCycleStartAt = paracetamolCycleStartAt
        self.cloudRecordName = cloudRecordName
    }

    /// Convenience: last dose for a given medication, sorted by timestamp descending.
    func lastDose(for medication: Medication) -> DoseLog? {
        doses
            .filter { $0.medication == medication.rawValue }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    /// Notification identifier for a child + medication pair.
    func notificationID(for medication: Medication) -> String {
        "\(name)-\(medication.rawValue)"
    }

    func doseNote(for medication: Medication) -> String? {
        switch medication {
        case .ibuprofen:
            return ibuprofenDoseNote
        case .paracetamol:
            return paracetamolDoseNote
        }
    }

    func setDoseNote(_ note: String?, for medication: Medication) {
        switch medication {
        case .ibuprofen:
            ibuprofenDoseNote = note
        case .paracetamol:
            paracetamolDoseNote = note
        }
    }

    func sessionEndedAt(for medication: Medication) -> Date? {
        switch medication {
        case .ibuprofen:
            return ibuprofenSessionEndedAt
        case .paracetamol:
            return paracetamolSessionEndedAt
        }
    }

    func setSessionEndedAt(_ timestamp: Date?, for medication: Medication) {
        switch medication {
        case .ibuprofen:
            ibuprofenSessionEndedAt = timestamp
        case .paracetamol:
            paracetamolSessionEndedAt = timestamp
        }
    }

    func cycleStartAt(for medication: Medication) -> Date? {
        switch medication {
        case .ibuprofen:
            return ibuprofenCycleStartAt
        case .paracetamol:
            return paracetamolCycleStartAt
        }
    }

    func setCycleStartAt(_ timestamp: Date?, for medication: Medication) {
        switch medication {
        case .ibuprofen:
            ibuprofenCycleStartAt = timestamp
        case .paracetamol:
            paracetamolCycleStartAt = timestamp
        }
    }
}
