import SwiftUI
import CloudKit
import UIKit

// MARK: - UIViewControllerRepresentable wrapping UICloudSharingController

struct CloudSharingView: UIViewControllerRepresentable {
    let container: CKContainer
    let share: CKShare?
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        if let share = share {
            // Existing share — let user manage participants or stop sharing.
            let controller = UICloudSharingController(share: share, container: container)
            controller.delegate = context.coordinator
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            return controller
        } else {
            // No share yet — prepare one and present the controller.
            let controller = UICloudSharingController { _, handler in
                Task {
                    do {
                        let rootRecord = CKRecord(recordType: "KidDoseRoot")
                        let shareRecord = CKShare(rootRecord: rootRecord)
                        shareRecord[CKShare.SystemFieldKey.title] = "KidDose Family" as CKRecordValue
                        _ = try await container.privateCloudDatabase.modifyRecords(
                            saving: [rootRecord, shareRecord],
                            deleting: []
                        )
                        handler(shareRecord, container, nil)
                    } catch {
                        handler(nil, container, error)
                    }
                }
            }
            controller.delegate = context.coordinator
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            return controller
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            print("[CloudSharing] Failed to save share: \(error)")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}

        func itemTitle(for csc: UICloudSharingController) -> String? { "KidDose Family" }
    }
}
