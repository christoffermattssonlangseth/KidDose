import SwiftUI
import SwiftData
import CloudKit

@main
struct KidDoseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let modelContainer: ModelContainer
    @State private var viewModel = DoseViewModel()

    init() {
        let schema = Schema([Child.self, DoseLog.self])

        // Try CloudKit-backed store first, then fall back to local-only.
        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.com.ChristofferMattssonLangseth.kiddose")
            )]
        ) {
            modelContainer = container
        } else {
            print("[KidDoseApp] CloudKit unavailable — using local store")
            modelContainer = (try? ModelContainer(for: schema)) ?? {
                // Last resort: in-memory store so the app at least launches.
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: [memoryConfig])
            }()
        }
    }

    var body: some Scene {
        WindowGroup {
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
                }
        }
    }
}
