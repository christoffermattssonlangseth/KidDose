import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(DoseViewModel.self) private var viewModel
    @Query(sort: \Child.name) private var children: [Child]

    @State private var selectedChildID: PersistentIdentifier?
    @State private var showAlarms = false

    var selectedChild: Child? {
        guard let id = selectedChildID else { return children.first }
        return children.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // iCloud banner
                    if !viewModel.iCloudAvailable {
                        iCloudBanner()
                    }

                    if children.isEmpty {
                        EmptyStateView()
                    } else {
                        // ── Child selector ──────────────────────────────
                        if children.count >= 4 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(children) { child in
                                        ChildChip(
                                            child: child,
                                            isSelected: selectedChild?.persistentModelID == child.persistentModelID
                                        ) {
                                            selectedChildID = child.persistentModelID
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        } else if children.count >= 2 {
                            Picker("Child", selection: Binding(
                                get: { selectedChild?.persistentModelID },
                                set: { selectedChildID = $0 }
                            )) {
                                ForEach(children) { child in
                                    Text(child.name).tag(Optional(child.persistentModelID))
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                        }

                        // ── Medication cards ────────────────────────────
                        if let child = selectedChild {
                            VStack(spacing: 16) {
                                ForEach(Medication.allCases, id: \.rawValue) { med in
                                    MedicationCard(medication: med, child: child)
                                        // Force re-creation (and State reset) when child changes
                                        // so the interval picker resets to the medication default.
                                        .id(child.persistentModelID)
                                }
                            }
                            .padding(.horizontal)

                            // ── Upcoming doses for this child ───────────
                            let upcoming = viewModel.upcomingDoses(for: [child])
                            if !upcoming.isEmpty {
                                UpcomingSection(items: upcoming)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("KidDose")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAlarms = true
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                }
            }
            .sheet(isPresented: $showAlarms) {
                ScheduledAlarmsView()
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                if selectedChildID == nil || !children.map(\.persistentModelID).contains(selectedChildID) {
                    selectedChildID = children.first?.persistentModelID
                }
            }
            .onChange(of: children.count) {
                if !children.map(\.persistentModelID).contains(selectedChildID) {
                    selectedChildID = children.first?.persistentModelID
                }
            }
        }
    }
}

// MARK: - Upcoming Section

struct UpcomingSection: View {
    let items: [ScheduledDose]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Upcoming Doses", systemImage: "calendar.badge.clock")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    UpcomingRow(item: item)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        }
    }
}

// MARK: - Upcoming Row

private struct UpcomingRow: View {
    let item: ScheduledDose

    var body: some View {
        HStack(spacing: 14) {
            // Medication icon
            Circle()
                .fill(item.medication.color.opacity(0.15))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: item.medication.iconName)
                        .foregroundStyle(item.medication.color)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.medication.displayName)
                    .font(.subheadline.bold())
                Text(formattedTime(item.nextDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Live countdown to this specific upcoming dose
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let remaining = item.nextDate.timeIntervalSince(context.date)
                if remaining > 0 {
                    Text(roughCountdown(remaining))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(item.medication.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(item.medication.color.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// "Today at 3:45 PM", "Tomorrow at 6:00 AM", "Wed at 9:15 AM"
    private func formattedTime(_ date: Date) -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let timeStr = formatter.string(from: date)

        if cal.isDateInToday(date) {
            return "Today at \(timeStr)"
        } else if cal.isDateInTomorrow(date) {
            return "Tomorrow at \(timeStr)"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            return "\(dayFormatter.string(from: date)) at \(timeStr)"
        }
    }

    /// Compact countdown for the upcoming row: "5h 30m", "45m"
    private func roughCountdown(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Child Chip (for 4+ children)

private struct ChildChip: View {
    let child: Child
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: child.colorHex))
                    .frame(width: 10, height: 10)
                Text(child.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color(hex: child.colorHex).opacity(0.2)
                    : Color(.secondarySystemBackground),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color(hex: child.colorHex) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No children added yet")
                .font(.title3.bold())
            Text("Add a child in the Children tab to start tracking doses.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
