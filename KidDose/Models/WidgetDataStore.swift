import Foundation

/// Snapshot of a single child's dose state, written by the main app and read by the widget extension.
struct WidgetChildSnapshot: Codable, Identifiable {
    var id: String { name }
    let name: String
    let colorHex: String
    /// The absolute date when the next ibuprofen dose is allowed. Nil if no doses recorded or session ended.
    let ibuprofenNextDate: Date?
    /// The absolute date when the next paracetamol dose is allowed. Nil if no doses recorded or session ended.
    let paracetamolNextDate: Date?
    /// True if at least one ibuprofen dose exists in the current cycle.
    let ibuprofenHasDoses: Bool
    /// True if at least one paracetamol dose exists in the current cycle.
    let paracetamolHasDoses: Bool
}

/// Shared data store between the main app and the widget extension via App Groups.
///
/// Setup required in Xcode:
///   1. Add the "App Groups" capability to both the KidDose target and the KidDoseWidgets target.
///   2. Create a group with the identifier below (or replace it with your own).
///   3. Add WidgetDataStore.swift to both targets (Target Membership in the File Inspector).
enum WidgetDataStore {
    // IMPORTANT: Replace with your actual App Group identifier.
    static let appGroupID = "group.com.yourname.kiddose"
    private static let snapshotsKey = "widgetChildSnapshots"

    static func write(_ snapshots: [WidgetChildSnapshot]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if let data = try? JSONEncoder().encode(snapshots) {
            defaults.set(data, forKey: snapshotsKey)
        }
    }

    static func read() -> [WidgetChildSnapshot] {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotsKey),
            let snapshots = try? JSONDecoder().decode([WidgetChildSnapshot].self, from: data)
        else { return [] }
        return snapshots
    }
}
