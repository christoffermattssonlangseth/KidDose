import UserNotifications
import Foundation

/// Manages local notification scheduling and permissions, including Critical Alerts.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private(set) var criticalAlertsGranted = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission Request

    func requestPermission() async {
        do {
            // Request standard + critical alert permissions.
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge, .criticalAlert]
            )
            criticalAlertsGranted = granted
        } catch {
            // criticalAlert may be denied by the OS or requires Apple entitlement.
            // Fall back to standard notifications.
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                criticalAlertsGranted = false
                _ = granted
            } catch {
                criticalAlertsGranted = false
            }
        }
    }

    // MARK: - Schedule Dose-Ready Notification

    /// Schedules a Critical Alert (or regular alert) when the next dose is allowed.
    func scheduleDoseReady(
        childName: String,
        medication: Medication,
        body: String,
        nextAllowedAt: Date
    ) {
        let identifier = notificationID(childName: childName, medication: medication)

        // Cancel any existing pending notification for this pair.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "\(medication.displayName) ready for \(childName)"
        content.body = body
        content.sound = criticalAlertsGranted
            ? UNNotificationSound.defaultCriticalSound(withAudioVolume: 1.0)
            : .default

        if criticalAlertsGranted {
            content.interruptionLevel = .critical
        }

        let interval = nextAllowedAt.timeIntervalSinceNow
        guard interval > 0 else { return }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Schedule Cross-Device Notification (regular priority)

    /// Fires when a CloudKit push tells us another device logged a dose.
    func schedulePartnerDoseNotification(
        partner: String,
        medication: String,
        childName: String,
        at time: Date
    ) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let timeString = formatter.string(from: time)

        let content = UNMutableNotificationContent()
        content.title = "Dose recorded"
        content.body = "\(partner) gave \(medication) to \(childName) at \(timeString)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Dose Warning

    /// Immediate, time-sensitive alert when a dose that was already given breaks a rule
    /// (e.g. a Watch dose logged too soon after a partner's dose).
    func postDoseWarning(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cancel

    func cancelDoseNotification(childName: String, medication: Medication) {
        let identifier = notificationID(childName: childName, medication: medication)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Clears every pending dose-ready notification. Used at launch before rescheduling
    /// so we drop orphans from renamed children, reinstalls, or deleted/edited doses.
    func cancelAllPendingDoseNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let medicationSuffixes = Medication.allCases.map { "-\($0.rawValue)" }
        let ids = pending
            .map(\.identifier)
            .filter { id in medicationSuffixes.contains(where: id.hasSuffix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Helpers

    func notificationID(childName: String, medication: Medication) -> String {
        "\(childName)-\(medication.rawValue)"
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Display notifications while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
