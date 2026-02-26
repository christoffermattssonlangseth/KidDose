import Foundation
import ActivityKit
import UIKit

enum LiveActivityLayoutStyle: String, CaseIterable, Identifiable {
    case compact
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .detailed: return "Detailed"
        }
    }
}

enum LiveActivityDisplayMode: String, CaseIterable, Identifiable {
    case always
    case thirtyMinutesBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Always"
        case .thirtyMinutesBefore: return "Before due"
        }
    }
}

enum LiveActivityDueSoonThreshold: Int, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) min"
    }
}

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private enum Keys {
        static let layoutStyle = "KidDose.liveActivity.layoutStyle"
        static let preferLargeText = "KidDose.liveActivity.preferLargeText"
        static let displayMode = "KidDose.liveActivity.displayMode"
        static let dueSoonThreshold = "KidDose.liveActivity.dueSoonThreshold"
    }

    private let defaults = UserDefaults.standard

    private init() {}

    private(set) var lastStatusMessage: String = "Not started yet."
    private(set) var lastErrorMessage: String?
    private(set) var lastRefreshAt: Date?

    var preferredLayoutStyle: LiveActivityLayoutStyle {
        get {
            let rawValue = defaults.string(forKey: Keys.layoutStyle) ?? LiveActivityLayoutStyle.detailed.rawValue
            return LiveActivityLayoutStyle(rawValue: rawValue) ?? .detailed
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.layoutStyle)
        }
    }

    var preferLargeText: Bool {
        get { defaults.bool(forKey: Keys.preferLargeText) }
        set { defaults.set(newValue, forKey: Keys.preferLargeText) }
    }

    var displayMode: LiveActivityDisplayMode {
        get {
            let rawValue = defaults.string(forKey: Keys.displayMode) ?? LiveActivityDisplayMode.always.rawValue
            return LiveActivityDisplayMode(rawValue: rawValue) ?? .always
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.displayMode)
        }
    }

    var dueSoonThreshold: LiveActivityDueSoonThreshold {
        get {
            let minutes = defaults.object(forKey: Keys.dueSoonThreshold) as? Int ?? LiveActivityDueSoonThreshold.thirty.rawValue
            return LiveActivityDueSoonThreshold(rawValue: minutes) ?? .thirty
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.dueSoonThreshold)
        }
    }

    private var activeActivity: Activity<KidDoseLiveActivityAttributes>? {
        Activity<KidDoseLiveActivityAttributes>.activities.first
    }

    private var isAppForegroundActive: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.activationState == .foregroundActive }
    }

    func refresh(children: [Child], using viewModel: DoseViewModel) {
        lastRefreshAt = .now

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastStatusMessage = "Live Activities are disabled in iOS settings."
            lastErrorMessage = nil
            return
        }

        // Preserve real overdue timestamps so widget mirrors Home countdown behavior.
        let upcoming = viewModel.upcomingDoses(for: children, clampToNow: false)
        guard let primary = upcoming.first else {
            lastStatusMessage = "No upcoming doses to show."
            lastErrorMessage = nil
            endAll()
            return
        }

        let shouldShowLiveActivity: Bool
        let thresholdMinutes = dueSoonThreshold.rawValue
        switch displayMode {
        case .always:
            shouldShowLiveActivity = true
        case .thirtyMinutesBefore:
            shouldShowLiveActivity = primary.nextDate.timeIntervalSinceNow <= Double(thresholdMinutes * 60)
        }

        if !shouldShowLiveActivity {
            if activeActivity != nil {
                endAll()
            }
            let minutesUntilDue = max(Int(ceil(primary.nextDate.timeIntervalSinceNow / 60)), 0)
            lastStatusMessage = "Live Activity will show \(thresholdMinutes) min before dose (\(minutesUntilDue) min left)."
            lastErrorMessage = nil
            return
        }

        let secondary = upcoming.dropFirst().first
        let primaryLastDose = viewModel.latestDoseInCurrentCycle(for: primary.medication, child: primary.child)
        let secondaryLastDose = secondary.flatMap {
            viewModel.latestDoseInCurrentCycle(for: $0.medication, child: $0.child)
        }
        let state = KidDoseLiveActivityAttributes.ContentState(
            primaryChildName: primary.child.name,
            primaryMedicationName: primary.medication.displayName,
            primaryMedicationSymbol: primary.medication.iconName,
            primaryNextDose: primary.nextDate,
            primaryLastDose: primaryLastDose?.timestamp,
            primaryIntervalHours: primary.intervalHours,
            primaryDoseNote: primary.child.doseNote(for: primary.medication),
            preferredLayoutStyle: preferredLayoutStyle.rawValue,
            preferLargeText: preferLargeText,
            secondaryChildName: secondary?.child.name,
            secondaryMedicationName: secondary?.medication.displayName,
            secondaryMedicationSymbol: secondary?.medication.iconName,
            secondaryNextDose: secondary?.nextDate,
            secondaryLastDose: secondaryLastDose?.timestamp,
            secondaryIntervalHours: secondary?.intervalHours,
            secondaryDoseNote: secondary.flatMap { $0.child.doseNote(for: $0.medication) }
        )

        let staleDate = max(primary.nextDate, Date.now).addingTimeInterval(6 * 3600)
        let content = ActivityContent(state: state, staleDate: staleDate)

        if let activity = activeActivity {
            lastStatusMessage = "Live Activity updated."
            lastErrorMessage = nil
            Task {
                await activity.update(content)
            }
            return
        }

        guard isAppForegroundActive else {
            lastStatusMessage = "Waiting for app to be foreground to start Live Activity."
            lastErrorMessage = nil
            return
        }

        let attributes = KidDoseLiveActivityAttributes(title: "KidDose")
        do {
            _ = try Activity<KidDoseLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            lastStatusMessage = "Live Activity started."
            lastErrorMessage = nil
        } catch {
            lastStatusMessage = "Failed to start Live Activity."
            lastErrorMessage = error.localizedDescription
            print("[LiveActivity] request failed: \(error)")
        }
    }

    func endAll() {
        let activities = Activity<KidDoseLiveActivityAttributes>.activities
        guard !activities.isEmpty else {
            lastStatusMessage = "No active Live Activity."
            return
        }

        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        lastStatusMessage = "Live Activity ended."
    }
}
