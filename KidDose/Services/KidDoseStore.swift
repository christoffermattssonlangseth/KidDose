import Foundation
import SwiftData

/// The single model container and view model shared by the app UI, Siri / Shortcuts
/// intents, and Lock Screen buttons, which can run while the UI is not on screen.
@MainActor
enum KidDoseStore {
    static let schema = Schema([Child.self, DoseLog.self, TemperatureLog.self])

    static let startup: (container: ModelContainer?, error: String?) = makeModelContainer()

    static var container: ModelContainer? { startup.container }

    static let viewModel = DoseViewModel()

    private static func makeModelContainer() -> (container: ModelContainer?, error: String?) {
        // 1) Preferred: CloudKit-backed store (when bundle id is configured).
        if let containerIdentifier = CloudKitConfig.containerIdentifier {
            do {
                let cloudConfig = ModelConfiguration(
                    cloudKitDatabase: .private(containerIdentifier)
                )
                return (try ModelContainer(for: schema, configurations: [cloudConfig]), nil)
            } catch {
                print("[KidDoseStore] CloudKit store init failed: \(error)")
            }
        } else {
            print("[KidDoseStore] CloudKit not configured — trying local store")
        }

        // 2) Fallback: local on-device store.
        do {
            let localConfig = ModelConfiguration(cloudKitDatabase: .none)
            return (try ModelContainer(for: schema, configurations: [localConfig]), nil)
        } catch {
            print("[KidDoseStore] Local store init failed: \(error)")
        }

        // 3) Last resort: in-memory store (no persisted data, but app launches).
        do {
            let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return (try ModelContainer(for: schema, configurations: [memoryConfig]), nil)
        } catch {
            let message = "Failed to initialize any ModelContainer: \(error)"
            print("[KidDoseStore] \(message)")
            return (nil, message)
        }
    }
}
