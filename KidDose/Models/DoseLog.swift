import SwiftData
import Foundation

@Model
final class DoseLog {
    var medication: String   // Medication.rawValue
    var timestamp: Date
    var givenBy: String      // Device owner's name at time of logging

    var child: Child?

    init(medication: Medication, timestamp: Date = .now, givenBy: String, child: Child) {
        self.medication = medication.rawValue
        self.timestamp = timestamp
        self.givenBy = givenBy
        self.child = child
    }

    var medicationEnum: Medication? {
        Medication(rawValue: medication)
    }

    /// Human-readable relative time, e.g. "2 hours ago".
    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: .now)
    }
}
