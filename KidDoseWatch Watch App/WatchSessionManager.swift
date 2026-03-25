import Foundation
import WatchConnectivity
import WidgetKit
import WatchKit

enum DoseLogRequestResult {
    case sent
    case queued
    case failed(String)

    var feedbackText: String {
        switch self {
        case .sent:
            return "Sent ✓"
        case .queued:
            return "Queued ✓"
        case let .failed(message):
            return message
        }
    }

    var isSuccess: Bool {
        switch self {
        case .sent, .queued:
            return true
        case .failed:
            return false
        }
    }
}

/// Manages WatchConnectivity on the Watch side.
/// Receives snapshots from the iPhone, updates the UI, and sends dose-log requests back.
@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    var snapshots: [WidgetChildSnapshot]

    private override init() {
        snapshots = WidgetDataStore.read()
        super.init()
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending Dose Requests

    /// Sends a dose-log request to the iPhone.
    /// Uses interactive messaging when reachable and falls back to background transfer otherwise.
    func requestDoseLog(childName: String, medication: String, intervalHours: Double) -> DoseLogRequestResult {
        guard WCSession.isSupported() else {
            return .failed("Watch sync unavailable")
        }

        let session = WCSession.default
        guard session.activationState == .activated else {
            session.activate()
            return .failed("Connecting to iPhone")
        }

        guard session.isCompanionAppInstalled else {
            return .failed("Install iPhone app first")
        }

        let message: [String: Any] = [
            "action": "logDose",
            "childName": childName,
            "medication": medication,
            "intervalHours": intervalHours
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("[WatchSessionManager] sendMessage error: \(error)")
            }
            return .sent
        }

        session.transferUserInfo(message)
        print("[WatchSessionManager] queued background dose-log request")
        return .queued
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("[WatchSessionManager] Activation error: \(error)")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handlePayload(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handlePayload(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handlePayload(message)
        replyHandler(["status": "ok"])
    }

    // MARK: - Private

    private func handlePayload(_ payload: [String: Any]) {
        guard
            let data = payload["snapshots"] as? Data,
            let newSnapshots = try? JSONDecoder().decode([WidgetChildSnapshot].self, from: data)
        else { return }

        DispatchQueue.main.async {
            self.applySnapshots(newSnapshots)
        }
    }

    private func applySnapshots(_ newSnapshots: [WidgetChildSnapshot]) {
        let oldSnapshots = snapshots

        // Detect transitions from "waiting" → "ready" for haptic feedback.
        for new in newSnapshots {
            if let old = oldSnapshots.first(where: { $0.name == new.name }) {
                let ibuprofenBecameReady = isNowReady(new: new.ibuprofenNextDate, newHas: new.ibuprofenHasDoses,
                                                       old: old.ibuprofenNextDate, oldHas: old.ibuprofenHasDoses)
                let paracetamolBecameReady = isNowReady(new: new.paracetamolNextDate, newHas: new.paracetamolHasDoses,
                                                         old: old.paracetamolNextDate, oldHas: old.paracetamolHasDoses)
                if ibuprofenBecameReady || paracetamolBecameReady {
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }

        snapshots = newSnapshots
        WidgetDataStore.write(newSnapshots)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Returns true if a dose transitioned from "waiting" to "ready".
    private func isNowReady(
        new nextDate: Date?,
        newHas hasDoses: Bool,
        old oldDate: Date?,
        oldHas oldHasDoses: Bool
    ) -> Bool {
        // Ready now: nextDate is nil (session ended / no doses) or in the past, and has doses.
        let nowReady = hasDoses && (nextDate == nil || nextDate! <= .now)
        // Was waiting before: had a future date.
        let wasWaiting = oldHasDoses && oldDate != nil && oldDate! > .now
        return nowReady && wasWaiting
    }
}
