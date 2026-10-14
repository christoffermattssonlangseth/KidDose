import SwiftUI
import SwiftData
import CloudKit
import LocalAuthentication
import Combine

@main
struct KidDoseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer?
    let startupError: String?
    @State private var viewModel: DoseViewModel
    @State private var appLock = AppLockService()

    init() {
        let startup = KidDoseStore.startup
        modelContainer = startup.container
        startupError = startup.error

        let initialViewModel = KidDoseStore.viewModel
        _viewModel = State(initialValue: initialViewModel)

        PhoneSessionManager.shared.activate()
        if let modelContainer {
            PhoneSessionManager.shared.onDoseLogRequest = { request in
                Task { @MainActor in
                    let ctx = modelContainer.mainContext
                    let children = (try? ctx.fetch(FetchDescriptor<Child>())) ?? []
                    // Match by stable ID first; the name is only a fallback for older Watch builds.
                    let matchedChild = request.childID.flatMap { id in children.first { $0.uid == id } }
                        ?? children.first { $0.name == request.childName }
                    guard
                        let child = matchedChild,
                        let medication = Medication(rawValue: request.medicationRaw)
                    else { return }
                    initialViewModel.logWatchDose(
                        medication: medication,
                        intervalHours: request.intervalHours,
                        timestamp: request.givenAt,
                        for: child,
                        context: ctx
                    )
                }
            }
        } else {
            PhoneSessionManager.shared.onDoseLogRequest = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ZStack {
                    ContentView()
                        .modelContainer(modelContainer)
                        .environment(viewModel)
                        .task {
                            appDelegate.modelContainer = modelContainer
                            viewModel.prepareStoredData(context: modelContainer.mainContext)

                            // Send current snapshots to Watch on launch.
                            // Small delay lets WCSession finish activating first.
                            try? await Task.sleep(for: .seconds(2))
                            viewModel.sendSnapshotsToWatch(context: modelContainer.mainContext)

                            // Request notification permission on first launch.
                            await NotificationManager.shared.requestPermission()

                            // Check iCloud sign-in status.
                            await viewModel.refreshiCloudStatus()

                            // Set up the CloudKit subscription for cross-device dose alerts.
                            viewModel.setupCloudKitSubscription()

                            if !viewModel.familySyncEnabled {
                                _ = await viewModel.refreshAcceptedFamily(context: modelContainer.mainContext)
                            }

                            // Pull family-shared records (if configured) on launch.
                            await viewModel.syncFamilyCloud(context: modelContainer.mainContext)
                            viewModel.refreshLiveActivity(context: modelContainer.mainContext)

                            // Rebuild pending dose-ready notifications from current DB
                            // state — restores alarms lost to reinstall/reboot and clears
                            // orphans left behind by renamed children or edited doses.
                            await viewModel.rescheduleAllDoseNotifications(
                                context: modelContainer.mainContext
                            )
                        }
                        .task {
                            // CloudKit pushes wake the app for most partner changes, so this is
                            // only a safety net. Polling slowly saves battery.
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(90))
                                guard viewModel.familySyncEnabled else { continue }
                                await viewModel.syncFamilyCloud(context: modelContainer.mainContext)
                            }
                        }
                        .task {
                            appLock.restoreSettings()
                            if appLock.isEnabled {
                                _ = await appLock.requestUnlock()
                            }
                        }

                    if appLock.isEnabled && !appLock.isUnlocked {
                        AppLockOverlay()
                    } else if appLock.isEnabled && scenePhase != .active {
                        // Hides medical details in the app switcher without forcing Face ID
                        // for things like pulling down Control Center.
                        PrivacyCover()
                    }
                }
                .environment(appLock)
                .onReceive(NotificationCenter.default.publisher(for: .cloudKitDidReceiveRemoteNotification)) { _ in
                    Task {
                        await viewModel.syncFamilyCloud(context: modelContainer.mainContext)
                    }
                }
            } else {
                StartupFailureView(message: startupError)
            }
        }
        .onChange(of: scenePhase) {
            guard let modelContainer else { return }
            switch scenePhase {
            case .active:
                Task {
                    if appLock.isEnabled && !appLock.isUnlocked {
                        _ = await appLock.requestUnlock()
                    }
                    await viewModel.syncFamilyCloud(context: modelContainer.mainContext)
                    viewModel.refreshLiveActivity(context: modelContainer.mainContext)
                }
            case .background:
                appLock.lock()
            case .inactive:
                // Control Center, notification banners and the app switcher make the app
                // inactive. Only a real trip to the background requires unlocking again.
                break
            @unknown default:
                break
            }
        }
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            Image(systemName: "lock.shield")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
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

@MainActor
@Observable
final class AppLockService {
    private enum Keys {
        static let enabled = "KidDose.security.appLockEnabled"
    }

    private let defaults = UserDefaults.standard
    var isEnabled: Bool = false
    var isUnlocked: Bool = true
    var isUnlocking: Bool = false
    var lastErrorMessage: String?

    func restoreSettings() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        isUnlocked = !isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        if !enabled {
            isUnlocked = true
            lastErrorMessage = nil
        } else {
            lock()
        }
    }

    func lock() {
        guard isEnabled else { return }
        isUnlocked = false
    }

    @discardableResult
    func requestUnlock() async -> Bool {
        guard isEnabled else {
            isUnlocked = true
            return true
        }
        guard !isUnlocked, !isUnlocking else { return isUnlocked }

        isUnlocking = true
        defer { isUnlocking = false }

        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            lastErrorMessage = authError?.localizedDescription
                ?? "Face ID / passcode is unavailable on this device."
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock KidDose to view medication history and timers."
            )
            if success {
                isUnlocked = true
                lastErrorMessage = nil
                return true
            }
            return false
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }
}

private struct AppLockOverlay: View {
    @Environment(AppLockService.self) private var appLock

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("KidDose is locked")
                    .font(.title3.bold())

                Text("Use Face ID or your device passcode to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        _ = await appLock.requestUnlock()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if appLock.isUnlocking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(appLock.isUnlocking ? "Unlocking..." : "Unlock")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appLock.isUnlocking)

                if let message = appLock.lastErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
        }
    }
}
