import SwiftUI
import SwiftData
import CloudKit

@main
struct KidDoseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer?
    let startupError: String?
    @State private var viewModel = DoseViewModel()

    init() {
        let startup = Self.makeModelContainer()
        modelContainer = startup.container
        startupError = startup.error
    }

    private static func makeModelContainer() -> (container: ModelContainer?, error: String?) {
        let schema = Schema([Child.self, DoseLog.self])

        // 1) Preferred: CloudKit-backed store (when bundle id is configured).
        if let containerIdentifier = CloudKitConfig.containerIdentifier {
            do {
                let cloudConfig = ModelConfiguration(
                    cloudKitDatabase: .private(containerIdentifier)
                )
                return (try ModelContainer(for: schema, configurations: [cloudConfig]), nil)
            } catch {
                print("[KidDoseApp] CloudKit store init failed: \(error)")
            }
        } else {
            print("[KidDoseApp] CloudKit not configured — trying local store")
        }

        // 2) Fallback: local on-device store.
        do {
            let localConfig = ModelConfiguration(
                cloudKitDatabase: .none
            )
            return (try ModelContainer(for: schema, configurations: [localConfig]), nil)
        } catch {
            print("[KidDoseApp] Local store init failed: \(error)")
        }

        // 3) Last resort: in-memory store (no persisted data, but app launches).
        do {
            let memoryConfig = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return (try ModelContainer(for: schema, configurations: [memoryConfig]), nil)
        } catch {
            let message = "Failed to initialize any ModelContainer: \(error)"
            print("[KidDoseApp] \(message)")
            return (nil, message)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .modelContainer(modelContainer)
                    .environment(viewModel)
                    .task {
                        appDelegate.modelContainer = modelContainer

                        // Request notification permission on first launch.
                        await NotificationManager.shared.requestPermission()

                        // Check iCloud sign-in status.
                        await viewModel.refreshiCloudStatus()

                        // Set up the CloudKit subscription for cross-device dose alerts.
                        viewModel.setupCloudKitSubscription()

                        // Pull family-shared records (if configured) on launch.
                        await viewModel.syncFamilyCloud(context: modelContainer.mainContext)
                    }
                    .task {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(15))

                            // Public-database family sync currently relies on pull updates.
                            // Polling keeps simulator + device reasonably in sync while both are open.
                            await viewModel.syncFamilyCloud(context: modelContainer.mainContext)
                        }
                    }
            } else {
                StartupFailureView(message: startupError)
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active, let modelContainer else { return }
            Task {
                await viewModel.syncFamilyCloud(context: modelContainer.mainContext)
            }
        }
    }
}

private struct StartupFailureView: View {
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KidDose couldn't start its data store.")
                .font(.title3.bold())
            Text("Try setting a real bundle identifier, then reinstalling the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
    }
}
