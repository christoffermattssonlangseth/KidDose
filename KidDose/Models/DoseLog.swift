import SwiftData
import Foundation

@Model
final class DoseLog {
    var medication: String   // Medication.rawValue
    var timestamp: Date
    var givenBy: String      // Device owner's name at time of logging
    var cloudRecordName: String?
    /// The interval (in hours) chosen when this dose was logged.
    /// 0.0 is a legacy sentinel meaning "use medication default" for records
    /// created before this field existed.
    var usedIntervalHours: Double

    var child: Child?

    init(
        medication: Medication,
        intervalHours: Double = 0,
        timestamp: Date = .now,
        givenBy: String,
        child: Child,
        cloudRecordName: String? = nil
    ) {
        self.medication = medication.rawValue
        self.timestamp = timestamp
        self.givenBy = givenBy
        self.cloudRecordName = cloudRecordName
        // If caller passes 0 (or omits), fall back to the medication's default.
        self.usedIntervalHours = intervalHours > 0 ? intervalHours : medication.intervalHours
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
