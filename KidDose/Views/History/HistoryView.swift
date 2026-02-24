import SwiftUI
import SwiftData

// MARK: - History mode

private enum HistoryMode: String, CaseIterable {
    case past     = "Past"
    case upcoming = "Upcoming"
}

// MARK: - HistoryView

struct HistoryView: View {
    @Query(sort: \Child.name) private var children: [Child]
    @Query(sort: \DoseLog.timestamp, order: .reverse) private var allDoses: [DoseLog]
    @Environment(DoseViewModel.self) private var viewModel

    @State private var mode: HistoryMode = .past
    @State private var selectedChildID: PersistentIdentifier? = nil   // nil = All

    // MARK: Computed

    private var filteredDoses: [DoseLog] {
        guard let id = selectedChildID else { return allDoses }
        return allDoses.filter { $0.child?.persistentModelID == id }
    }

    private var filteredChildren: [Child] {
        guard let id = selectedChildID else { return Array(children) }
        return children.filter { $0.persistentModelID == id }
    }

    private var statsMap: [String: Int] {
        var result: [String: Int] = [:]
        for med in Medication.allCases {
            result[med.displayName] = filteredDoses.filter { $0.medication == med.rawValue }.count
        }
        return result
    }

    private var upcomingItems: [ScheduledDose] {
        viewModel.upcomingDoses(for: filteredChildren)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Mode toggle (Past / Upcoming) ────────────────────
                Picker("Mode", selection: $mode) {
                    ForEach(HistoryMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))

                Divider()

                // ── Child filter chips ───────────────────────────────
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            label: "All",
                            isSelected: selectedChildID == nil,
                            color: .accentColor
                        ) { selectedChildID = nil }

                        ForEach(children) { child in
                            FilterChip(
                                label: child.name,
                                isSelected: selectedChildID == child.persistentModelID,
                                color: Color(hex: child.colorHex)
                            ) { selectedChildID = child.persistentModelID }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))

                Divider()

                // ── Content ──────────────────────────────────────────
                switch mode {
                case .past:
                    pastContent
                case .upcoming:
                    upcomingContent
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Past content

    @ViewBuilder
    private var pastContent: some View {
        // Stats summary
        StatsRowView(stats: statsMap)
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))

        Divider()

        if filteredDoses.isEmpty {
            Spacer()
            Text("No doses recorded")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List(filteredDoses) { dose in
                DoseRowView(dose: dose)
            }
            .listStyle(.plain)
        }
    }

    // MARK: Upcoming content

    @ViewBuilder
    private var upcomingContent: some View {
        if upcomingItems.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("All doses are ready now")
                    .font(.headline)
                Text("No upcoming dose windows to show.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            List(upcomingItems) { item in
                UpcomingHistoryRow(item: item)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Upcoming History Row

private struct UpcomingHistoryRow: View {
    let item: ScheduledDose

    var body: some View {
        HStack(spacing: 14) {
            // Medication badge
            Circle()
                .fill(item.medication.color.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: item.medication.iconName)
                        .foregroundStyle(item.medication.color)
                }

            VStack(alignment: .leading, spacing: 3) {
                // Child · Medication
                HStack {
                    Text(item.child.name)
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(item.medication.displayName)
                        .font(.subheadline)
                        .foregroundStyle(item.medication.color)
                }
                // Absolute time label
                Text(formattedAbsoluteTime(item.nextDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Live countdown updating every minute
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let remaining = item.nextDate.timeIntervalSince(context.date)
                if remaining > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(roughCountdown(remaining))
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundStyle(item.medication.color)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedAbsoluteTime(_ date: Date) -> String {
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.timeStyle = .short
        tf.dateStyle = .none
        let timeStr = tf.string(from: date)

        if cal.isDateInToday(date)    { return "Today at \(timeStr)" }
        if cal.isDateInTomorrow(date) { return "Tomorrow at \(timeStr)" }
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        return "\(df.string(from: date)) at \(timeStr)"
    }

    private func roughCountdown(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? color.opacity(0.18) : Color(.tertiarySystemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? color : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stats Row

private struct StatsRowView: View {
    let stats: [String: Int]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Medication.allCases, id: \.rawValue) { med in
                HStack(spacing: 6) {
                    Image(systemName: med.iconName)
                        .foregroundStyle(med.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(med.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(stats[med.displayName] ?? 0) doses")
                            .font(.subheadline.bold())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Dose Row (Past)

private struct DoseRowView: View {
    let dose: DoseLog

    var medicationColor: Color { dose.medicationEnum?.color ?? .gray }
    var medicationIcon: String { dose.medicationEnum?.iconName ?? "pill" }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(medicationColor.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: medicationIcon)
                        .foregroundStyle(medicationColor)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(dose.child?.name ?? "Unknown")
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(dose.medication.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(medicationColor)
                }
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text(dose.givenBy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Show which interval was used if it differs from the default
                    if let med = dose.medicationEnum,
                       dose.usedIntervalHours > 0,
                       dose.usedIntervalHours != med.intervalHours {
                        Text("· \(Int(dose.usedIntervalHours))h interval")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(dose.relativeTimestamp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}
