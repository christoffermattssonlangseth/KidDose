import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(DoseViewModel.self) private var viewModel
    @Query(sort: \Child.name) private var children: [Child]

    @State private var selectedChildID: PersistentIdentifier?
    @State private var showAlarms = false
    @State private var showFullSchedule = false

    private var resolvedSelectedChildID: PersistentIdentifier? {
        if let selectedChildID { return selectedChildID }
        return children.first?.persistentModelID
    }

    var selectedChild: Child? {
        guard let id = resolvedSelectedChildID else { return nil }
        return children.first { $0.persistentModelID == id }
    }

    var body: some View {
            NavigationStack {
                ScrollView {
                VStack(spacing: 8) {

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
                                HStack(spacing: 8) {
                                    ForEach(children) { child in
                                        ChildChip(
                                            child: child,
                                            isSelected: resolvedSelectedChildID == child.persistentModelID
                                        ) {
                                            selectedChildID = child.persistentModelID
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        } else if children.count >= 2 {
                            Picker(
                                "Child",
                                selection: Binding<PersistentIdentifier?>(
                                    get: { selectedChildID },
                                    set: { newValue in selectedChildID = newValue }
                                )
                            ) {
                                ForEach(children) { child in
                                    Text(child.name).tag(Optional<PersistentIdentifier>(child.persistentModelID))
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                        }

                        // ── Medication cards ────────────────────────────
                        if let child = selectedChild {
                            VStack(spacing: 6) {
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
                                UpcomingSection(items: upcoming) {
                                    showFullSchedule = true
                                }
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
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
            .sheet(isPresented: $showFullSchedule) {
                if let child = selectedChild {
                    FullScheduleView(child: child)
                        .presentationDetents([.large])
                }
            }
            .onAppear {
                validateSelectedChild()
            }
            .onChange(of: children.count) {
                validateSelectedChild()
            }
        }
    }

    private func validateSelectedChild() {
        guard let selectedChildID else {
            self.selectedChildID = children.first?.persistentModelID
            return
        }

        if !children.contains(where: { $0.persistentModelID == selectedChildID }) {
            self.selectedChildID = children.first?.persistentModelID
        }
    }
}

// MARK: - Upcoming Section

struct UpcomingSection: View {
    let items: [ScheduledDose]
    let onViewFullSchedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Upcoming Doses", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Full schedule") {
                    onViewFullSchedule()
                }
                .font(.caption.weight(.semibold))
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    UpcomingRow(item: item)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 46)
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
        HStack(spacing: 10) {
            // Medication icon
            Circle()
                .fill(item.medication.color.opacity(0.15))
                .frame(width: 34, height: 34)
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
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.medication.color.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No children added yet")
                .font(.title3.bold())
            Text("Add a child in the Children tab to start tracking doses.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }
}
