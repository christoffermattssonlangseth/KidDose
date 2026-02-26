import Foundation
import ActivityKit

struct KidDoseLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var primaryChildName: String
        var primaryMedicationName: String
        var primaryMedicationSymbol: String
        var primaryNextDose: Date
        var primaryLastDose: Date?
        var primaryIntervalHours: Double?
        var primaryDoseNote: String?
        var preferredLayoutStyle: String?
        var preferLargeText: Bool?
        var secondaryChildName: String?
        var secondaryMedicationName: String?
        var secondaryMedicationSymbol: String?
        var secondaryNextDose: Date?
        var secondaryLastDose: Date?
        var secondaryIntervalHours: Double?
        var secondaryDoseNote: String?
    }

    var title: String
}
