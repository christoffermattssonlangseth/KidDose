import UIKit
import SwiftData
import CloudKit

/// AppDelegate handles remote push notifications from CloudKit subscriptions.
final class AppDelegate: NSObject, UIApplicationDelegate {

    // Injected from App entry point so we can refresh the context on push.
    var modelContainer: ModelContainer?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register only when CloudKit/push is actually available for this build/account.
        Task {
            let cloudAvailable = await CloudKitService.shared.checkiCloudStatus()
            guard cloudAvailable else { return }
            await MainActor.run {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit manages its own subscriptions; no manual token upload needed.
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Remote notification registration failed: \(error)")
    }

    // MARK: - Silent Push (CloudKit subscription payload)

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            if let container = modelContainer {
                let context = ModelContext(container)
                await CloudKitService.shared.handleRemoteNotification(
                    userInfo: userInfo,
                    modelContext: context
                )
            }
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            let context = modelContainer.map(ModelContext.init)
            _ = await FamilyCloudSyncService.shared.acceptShare(
                metadata: cloudKitShareMetadata,
                context: context
            )
        }
    }
}
