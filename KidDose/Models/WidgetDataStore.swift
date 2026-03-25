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
///   1. Add the "App Groups" capability to the KidDose app, the widget extension, and the watch app.
///   2. Ensure the derived app group `group.<root bundle identifier>` exists in your developer account.
///   3. Add WidgetDataStore.swift to the targets that read or write these snapshots.
enum WidgetDataStore {
    private static let infoPlistKey = "KidDoseAppGroupIdentifier"
    private static let snapshotsKey = "widgetChildSnapshots"

    private static var appGroupID: String? {
        guard
            let configured = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
            !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !configured.contains("$(")
        else {
            assertionFailure("Missing \(infoPlistKey) in \(Bundle.main.bundleIdentifier ?? "unknown bundle").")
            return nil
        }
        return configured
    }

    private static var sharedDefaults: UserDefaults? {
        guard let appGroupID else { return nil }
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            assertionFailure("Unable to open shared defaults for app group \(appGroupID). Check App Groups capabilities for all targets.")
            return nil
        }
        return defaults
    }

    static func write(_ snapshots: [WidgetChildSnapshot]) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(snapshots) {
            defaults.set(data, forKey: snapshotsKey)
        }
    }

    static func read() -> [WidgetChildSnapshot] {
        guard
            let defaults = sharedDefaults,
            let data = defaults.data(forKey: snapshotsKey),
            let snapshots = try? JSONDecoder().decode([WidgetChildSnapshot].self, from: data)
        else { return [] }
        return snapshots
    }
}
