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
        if let share {
            // Existing share — let user manage participants or stop sharing.
            return makeSharingController(with: share, coordinator: context.coordinator)
        }

        // No share yet: create one first, then present a non-deprecated sharing controller.
        let bootstrap = CloudShareBootstrapViewController(container: container)
        bootstrap.makeController = { share in
            makeSharingController(with: share, coordinator: context.coordinator)
        }
        return bootstrap
    }

    private func makeSharingController(
        with share: CKShare,
        coordinator: Coordinator
    ) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
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

private final class CloudShareBootstrapViewController: UIViewController {
    let container: CKContainer
    var makeController: ((CKShare) -> UICloudSharingController)?

    private let spinner = UIActivityIndicatorView(style: .large)
    private var hasStarted = false

    init(container: CKContainer) {
        self.container = container
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        spinner.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let share = try await self.createShare()
                await MainActor.run {
                    self.presentSharingController(share: share)
                }
            } catch {
                await MainActor.run {
                    self.presentCreationError(error)
                }
            }
        }
    }

    private func createShare() async throws -> CKShare {
        let rootRecord = CKRecord(recordType: "KidDoseRoot")
        let shareRecord = CKShare(rootRecord: rootRecord)
        shareRecord[CKShare.SystemFieldKey.title] = "KidDose Family" as CKRecordValue

        _ = try await container.privateCloudDatabase.modifyRecords(
            saving: [rootRecord, shareRecord],
            deleting: []
        )
        return shareRecord
    }

    private func presentSharingController(share: CKShare) {
        guard let makeController else { return }
        let controller = makeController(share)
        present(controller, animated: true)
    }

    private func presentCreationError(_ error: Error) {
        let alert = UIAlertController(
            title: "Unable to Start Sharing",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(
                title: "Close",
                style: .default,
                handler: { [weak self] _ in
                    self?.dismiss(animated: true)
                }
            )
        )
        present(alert, animated: true)
    }
}
