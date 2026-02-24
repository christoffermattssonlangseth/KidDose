import SwiftUI
import SwiftData

@main
struct KidDoseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var viewModel = DoseViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [Child.self, DoseLog.self])
                .environment(viewModel)
                .task {
                    // Request notification permission on first launch.
                    await NotificationManager.shared.requestPermission()

                    // Check iCloud sign-in status.
                    await viewModel.refreshiCloudStatus()
                }
        }
    }
}
