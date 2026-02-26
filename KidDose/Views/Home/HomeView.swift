import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Child.name) private var children: [Child]

    @State private var selectedChildID: PersistentIdentifier?
    @State private var showAlarms = false
    @State private var showFullSchedule = false
    @State private var showStartNewCycleConfirm = false

    private var visibleChildren: [Child] {
        viewModel.visibleChildrenForCurrentFamily(children)
    }

    private var isWaitingForFamilyChildren: Bool {
        viewModel.familySyncEnabled && !viewModel.familySyncOwner && visibleChildren.isEmpty
    }

    private var resolvedSelectedChildID: PersistentIdentifier? {
        if let selectedChildID { return selectedChildID }
        return visibleChildren.first?.persistentModelID
    }

    var selectedChild: Child? {
        guard let id = resolvedSelectedChildID else { return nil }
        return visibleChildren.first { $0.persistentModelID == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {

                    // iCloud banner
                    if !viewModel.iCloudAvailable {
                        iCloudBanner()
                    }

                    if visibleChildren.isEmpty {
                        EmptyStateView(isWaitingForFamilyChildren: isWaitingForFamilyChildren)
                    } else {
                        // ── Child selector ──────────────────────────────
                        if visibleChildren.count >= 4 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(visibleChildren) { child in
                                        ChildChip(
                                            child: child,
                                            isSelected: resolvedSelectedChildID == child.persistentModelID
                                        ) {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedChildID = child.persistentModelID
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        } else if visibleChildren.count >= 2 {
                            Picker(
                                "Child",
                                selection: Binding<PersistentIdentifier?>(
                                    get: { selectedChildID },
                                    set: { newValue in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedChildID = newValue
                                        }
                                    }
                                )
                            ) {
                                ForEach(visibleChildren) { child in
                                    Text(child.name).tag(Optional<PersistentIdentifier>(child.persistentModelID))
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                        }

                        if let child = selectedChild {
                            let upcoming = viewModel.upcomingDoses(for: [child])

                            if let next = upcoming.first {
                                NextDoseSection(
                                    item: next,
                                    additionalCount: max(0, upcoming.count - 1)
                                ) {
                                    showFullSchedule = true
                                }
                                .padding(.horizontal)
                                .transition(.opacity)
                            }

                            // ── Medication cards ────────────────────────────
                            // .id on the VStack (not individual cards) so the whole
                            // group resets State atomically and can fade as one unit.
                            VStack(spacing: 8) {
                                ForEach(Medication.allCases, id: \.rawValue) { med in
                                    MedicationCard(medication: med, child: child)
                                }
                            }
                            .id(child.persistentModelID)
                            .transition(.opacity)
                            .padding(.horizontal)

                            Button {
                                showStartNewCycleConfirm = true
                            } label: {
                                Label("Start New Infection Cycle", systemImage: "arrow.counterclockwise.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, KidDoseLayout.compactVerticalPadding)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 8)
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
            .confirmationDialog(
                "Start new infection cycle?",
                isPresented: $showStartNewCycleConfirm,
                titleVisibility: .visible
            ) {
                if let child = selectedChild {
                    Button("Start New Cycle") {
                        viewModel.startNewInfectionCycle(for: child, context: context)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This resets Home timers and schedules for this child but keeps all history.")
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
            self.selectedChildID = visibleChildren.first?.persistentModelID
            return
        }

        if !visibleChildren.contains(where: { $0.persistentModelID == selectedChildID }) {
            self.selectedChildID = visibleChildren.first?.persistentModelID
        }
    }
}

// MARK: - Next Dose

struct NextDoseSection: View {
    let item: ScheduledDose
    let additionalCount: Int
    let onViewFullSchedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Next Dose", systemImage: "clock.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if additionalCount > 0 {
                    Text("+\(additionalCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("View all") {
                    onViewFullSchedule()
                }
                .font(.caption.weight(.semibold))
            }

            NextDoseRow(item: item)
        }
        .padding(12)
        .kidDoseCardSurface()
    }
}

// MARK: - Next Dose Row

private struct NextDoseRow: View {
    let item: ScheduledDose

    var body: some View {
        HStack(spacing: 10) {
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
                Text(item.child.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formattedTime(item.nextDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let remaining = item.nextDate.timeIntervalSince(context.date)
                if remaining > 0 {
                    Text(roughCountdown(remaining))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(item.medication.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.medication.color.opacity(0.12), in: Capsule())
                } else {
                    Text("now")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

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
            .padding(.horizontal, KidDoseLayout.compactHorizontalPadding)
            .padding(.vertical, KidDoseLayout.compactVerticalPadding)
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
    let isWaitingForFamilyChildren: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(isWaitingForFamilyChildren ? "Waiting for family data" : "No children added yet")
                .font(.title3.bold())
            Text(
                isWaitingForFamilyChildren
                    ? "Family sharing is connected. Pull to sync from the Settings tab, then this screen updates automatically."
                    : "Add a child in the Settings tab to start tracking doses."
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }
}
