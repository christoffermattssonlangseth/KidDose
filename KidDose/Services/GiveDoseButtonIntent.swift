import AppIntents
import Foundation

/// Backs the "Give dose" buttons in the Live Activity and Lock Screen widget.
///
/// It is a `LiveActivityIntent`, so iOS runs it in the app's process even when tapped in the
/// widget; that is where the data store, family sync and notifications live. The first tap
/// only arms the button ("Tap again to give"); a second tap within a few seconds logs the dose,
/// so a stray touch on the Lock Screen can't record a dose.
struct GiveDoseButtonIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Give Dose from Lock Screen"
    static let description = IntentDescription("Tap once to arm, then again within a few seconds to log the dose.")
    static let isDiscoverable = false

    @Parameter(title: "Child ID")
    var childID: String

    @Parameter(title: "Medication")
    var medication: String

    init() {}

    init(childID: String, medication: Medication) {
        self.childID = childID
        self.medication = medication.rawValue
    }

    func perform() async throws -> some IntentResult {
        await LockScreenDoseRouter.handleTap(childID: childID, medication: medication)
        return .result()
    }
}
