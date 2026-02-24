import SwiftUI
import UserNotifications

/// Shows all pending local notifications that are currently scheduled.
struct ScheduledAlarmsView: View {
    @State private var alarms: [PendingAlarm] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if alarms.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("No alarms scheduled")
                            .font(.headline)
                        Text("Alarms are set automatically when you log a dose.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(alarms) { alarm in
                        AlarmRow(alarm: alarm)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Scheduled Alarms")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadAlarms() }
        }
    }

    private func loadAlarms() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()

        let parsed: [PendingAlarm] = requests.compactMap { request in
            guard
                let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
                let fireDate = trigger.nextTriggerDate(),
                let lastHyphen = request.identifier.lastIndex(of: "-")
            else { return nil }

            let medRaw = String(request.identifier[request.identifier.index(after: lastHyphen)...])
            let childName = String(request.identifier[..<lastHyphen])

            guard let medication = Medication(rawValue: medRaw) else { return nil }
            return PendingAlarm(id: request.identifier, childName: childName, medication: medication, fireDate: fireDate)
        }
        .sorted { $0.fireDate < $1.fireDate }

        alarms = parsed
        isLoading = false
    }
}

// MARK: - Model

struct PendingAlarm: Identifiable {
    let id: String
    let childName: String
    let medication: Medication
    let fireDate: Date
}

// MARK: - Row

private struct AlarmRow: View {
    let alarm: PendingAlarm

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(alarm.medication.color.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: alarm.medication.iconName)
                        .foregroundStyle(alarm.medication.color)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(alarm.childName)
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(alarm.medication.displayName)
                        .font(.subheadline)
                        .foregroundStyle(alarm.medication.color)
                }
                Text(formattedFireDate(alarm.fireDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let remaining = alarm.fireDate.timeIntervalSince(context.date)
                if remaining > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(roughCountdown(remaining))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(alarm.medication.color)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedFireDate(_ date: Date) -> String {
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.timeStyle = .short
        tf.dateStyle = .none
        let time = tf.string(from: date)
        if cal.isDateInToday(date) { return "Today at \(time)" }
        if cal.isDateInTomorrow(date) { return "Tomorrow at \(time)" }
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        return "\(df.string(from: date)) at \(time)"
    }

    private func roughCountdown(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
