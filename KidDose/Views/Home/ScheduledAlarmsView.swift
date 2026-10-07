import SwiftUI
import SwiftData

/// Shows upcoming/overdue dose windows derived from latest logged doses.
struct ScheduledAlarmsView: View {
    @Query(sort: \Child.name) private var children: [Child]
    @Environment(DoseViewModel.self) private var viewModel

    private var alarms: [ScheduledAlarm] {
        var items: [ScheduledAlarm] = []

        for child in children {
            for medication in Medication.allCases {
                guard let fireDate = viewModel.nextAllowedDate(for: medication, child: child) else { continue }
                items.append(
                    ScheduledAlarm(
                        childName: child.name,
                        medication: medication,
                        fireDate: fireDate
                    )
                )
            }
        }

        // Past due alarms first (most overdue), then upcoming soonest first.
        return items.sorted { lhs, rhs in
            if lhs.fireDate < .now, rhs.fireDate < .now {
                return lhs.fireDate > rhs.fireDate
            }
            if lhs.fireDate < .now { return true }
            if rhs.fireDate < .now { return false }
            return lhs.fireDate < rhs.fireDate
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if alarms.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("No alarms available")
                            .font(.headline)
                        Text("Log a dose to see the next due time.")
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
        }
    }
}

private struct ScheduledAlarm: Identifiable {
    let id = UUID()
    let childName: String
    let medication: Medication
    let fireDate: Date
}

private struct AlarmRow: View {
    let alarm: ScheduledAlarm

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(alarm.medication.color.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: alarm.medication.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(alarm.childName)
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(alarm.medication.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
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
                            .foregroundStyle(.primary)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(alarm.medication.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("Overdue", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(roughCountdown(-remaining))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                    }
                }
            }
        }
        .padding(.vertical, 3)
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
        let totalMinutes = max(0, Int(interval / 60))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
