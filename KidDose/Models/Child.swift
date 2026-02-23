import SwiftData
import Foundation

@Model
final class Child {
    var name: String
    var colorHex: String

    @Relationship(deleteRule: .cascade, inverse: \DoseLog.child)
    var doses: [DoseLog] = []

    init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
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
}
