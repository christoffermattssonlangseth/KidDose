import Foundation
import WatchConnectivity

/// Manages WatchConnectivity on the iPhone side.
/// The iPhone is the source of truth; it sends snapshots to the Watch
/// and handles dose-log requests coming back from the Watch.
final class PhoneSessionManager: NSObject, WCSessionDelegate {

    private struct PendingDoseLogRequest {
        let childName: String
        let medicationRaw: String
        let intervalHours: Double
    }

    static let shared = PhoneSessionManager()

    /// Called on the main actor when the Watch requests a dose log.
    /// Parameters: childName, medicationRawValue, intervalHours
    var onDoseLogRequest: ((String, String, Double) -> Void)? {
        didSet {
            flushPendingDoseLogRequests()
        }
    }

    private var pendingDoseLogRequests: [PendingDoseLogRequest] = []

    private override init() {
        super.init()
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending Snapshots

    /// Encodes snapshots as JSON and sends them to the Watch.
    /// Uses `updateApplicationContext` for background delivery and
    /// `sendMessage` when the Watch is immediately reachable.
    func sendSnapshots(_ snapshots: [WidgetChildSnapshot]) {
        guard WCSession.isSupported() else {
            print("[PhoneSessionManager] WCSession not supported")
            return
        }
        let session = WCSession.default
        print("[PhoneSessionManager] sendSnapshots — state: \(session.activationState.rawValue), paired: \(session.isPaired), watchAppInstalled: \(session.isWatchAppInstalled), reachable: \(session.isReachable), snapshotCount: \(snapshots.count)")
        guard session.activationState == .activated else {
            print("[PhoneSessionManager] Not activated, skipping send")
            return
        }

        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        let payload: [String: Any] = ["snapshots": data]

        // Background delivery (survives Watch sleep).
        do {
            try session.updateApplicationContext(payload)
            print("[PhoneSessionManager] updateApplicationContext succeeded")
        } catch {
            print("[PhoneSessionManager] updateApplicationContext error: \(error)")
        }

        // Foreground delivery when Watch app is reachable.
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[PhoneSessionManager] sendMessage error: \(error)")
            }
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("[PhoneSessionManager] Activation error: \(error)")
        } else {
            print("[PhoneSessionManager] Activated with state: \(activationState.rawValue)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingPayload(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleIncomingPayload(message)
        replyHandler(["status": "ok"])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleIncomingPayload(userInfo)
    }

    // MARK: - Private

    private func handleIncomingPayload(_ message: [String: Any]) {
        guard
            message["action"] as? String == "logDose",
            let childName = message["childName"] as? String,
            let medicationRaw = message["medication"] as? String,
            let intervalHours = message["intervalHours"] as? Double
        else { return }

        DispatchQueue.main.async {
            if let onDoseLogRequest = self.onDoseLogRequest {
                onDoseLogRequest(childName, medicationRaw, intervalHours)
            } else {
                self.pendingDoseLogRequests.append(
                    PendingDoseLogRequest(
                        childName: childName,
                        medicationRaw: medicationRaw,
                        intervalHours: intervalHours
                    )
                )
            }
        }
    }

    private func flushPendingDoseLogRequests() {
        guard let onDoseLogRequest, !pendingDoseLogRequests.isEmpty else { return }

        let pendingRequests = pendingDoseLogRequests
        pendingDoseLogRequests.removeAll()

        for request in pendingRequests {
            onDoseLogRequest(request.childName, request.medicationRaw, request.intervalHours)
        }
    }
}
