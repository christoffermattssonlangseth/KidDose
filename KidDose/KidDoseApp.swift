import SwiftUI
import SwiftData
import CloudKit

@main
struct KidDoseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    let modelContainer: ModelContainer
    @State private var viewModel = DoseViewModel()

    init() {
        // Configure SwiftData with CloudKit sync.
        let schema = Schema([Child.self, DoseLog.self])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.yourname.kiddose")
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback: local-only storage if CloudKit container cannot be reached.
            print("[KidDoseApp] CloudKit container error — falling back to local store: \(error)")
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try! ModelContainer(for: schema, configurations: [localConfig])
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
