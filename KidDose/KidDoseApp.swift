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
        let startup = Self.makeModelContainer()
        modelContainer = startup.container
        startupError = startup.error

        let initialViewModel = DoseViewModel()
        _viewModel = State(initialValue: initialViewModel)

        PhoneSessionManager.shared.activate()
        if let modelContainer {
            PhoneSessionManager.shared.onDoseLogRequest = { childName, medicationRaw, intervalHours in
                Task { @MainActor in
                    let ctx = modelContainer.mainContext
                    let children = (try? ctx.fetch(FetchDescriptor<Child>())) ?? []
                    guard
                        let child = children.first(where: { $0.name == childName }),
                        let medication = Medication(rawValue: medicationRaw)
                    else { return }
                    initialViewModel.logDose(
                        medication: medication,
                        intervalHours: intervalHours,
                        for: child,
                        context: ctx
                    )
                }
            }
        } else {
            PhoneSessionManager.shared.onDoseLogRequest = nil
        }
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
                ZStack {
                    ContentView()
                        .modelContainer(modelContainer)
                        .environment(viewModel)
                        .task {
                            appDelegate.modelContainer = modelContainer

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
                        }
                        .task {
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(15))

                                // Family sync relies on pull updates while both devices are open.
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
            case .inactive, .background:
                appLock.lock()
            @unknown default:
                break
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
