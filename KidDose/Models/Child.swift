import SwiftData
import Foundation

@Model
final class Child {
    var name: String
    var colorHex: String
    var cloudRecordName: String?
    var ibuprofenDoseNote: String?
    var paracetamolDoseNote: String?

    @Relationship(deleteRule: .cascade, inverse: \DoseLog.child)
    var doses: [DoseLog] = []

    init(
        name: String,
        colorHex: String,
        ibuprofenDoseNote: String? = nil,
        paracetamolDoseNote: String? = nil,
        cloudRecordName: String? = nil
    ) {
        self.name = name
        self.colorHex = colorHex
        self.ibuprofenDoseNote = ibuprofenDoseNote
        self.paracetamolDoseNote = paracetamolDoseNote
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
}
