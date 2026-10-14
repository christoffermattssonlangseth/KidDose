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
                VStack(spacing: 14) {

                    // iCloud banner
                    if !viewModel.iCloudAvailable {
                        iCloudBanner()
                    }

                    if visibleChildren.isEmpty {
                        EmptyStateView(isWaitingForFamilyChildren: isWaitingForFamilyChildren)
                    } else {
                        // ── Child selector ──────────────────────────────
                        if visibleChildren.count == 1, let only = visibleChildren.first {
                            ChildHeader(child: only)
                                .padding(.horizontal)
                        } else if visibleChildren.count >= 2 {
                            ChildSwitcher(
                                children: visibleChildren,
                                selectedID: resolvedSelectedChildID
                            ) { id in
                                withAnimation(.snappy) {
                                    selectedChildID = id
                                }
                            }
                            .padding(.horizontal)
                        }

                        if let child = selectedChild {
                            // ── Medication cards ────────────────────────────
                            // .id on the VStack (not individual cards) so the whole
                            // group resets State atomically and can fade as one unit.
                            VStack(spacing: 12) {
                                ForEach(Medication.allCases, id: \.rawValue) { med in
                                    MedicationCard(medication: med, child: child)
                                        .kidDoseScrollDepth()
                                }
                            }
                            .id(child.persistentModelID)
                            .transition(.blurReplace)
                            .padding(.horizontal)

                            Button {
                                showStartNewCycleConfirm = true
                            } label: {
                                Label("Start New Infection Cycle", systemImage: "arrow.counterclockwise.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, KidDoseLayout.compactVerticalPadding)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .kidDoseSecondaryButton()
                            .controlSize(.regular)
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("KidDose")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selectedChild != nil {
                        Button {
                            showFullSchedule = true
                        } label: {
                            Label("Schedule", systemImage: "calendar")
                        }
                    }
                    Button {
                        showAlarms = true
                    } label: {
                        Label("Alarms", systemImage: "bell.badge")
                            .symbolRenderingMode(.hierarchical)
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

// MARK: - Child Header (single child)

/// Names the child when there is only one, since the switcher is hidden then.
private struct ChildHeader: View {
    let child: Child

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: child.colorHex))
                .frame(width: 26, height: 26)
                .overlay {
                    Text(String(child.name.prefix(1)).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            Text(child.name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Child Switcher

/// Avatar bar with a selection highlight that slides between children.
/// Up to three children share the width like a segmented control; more scroll.
private struct ChildSwitcher: View {
    let children: [Child]
    let selectedID: PersistentIdentifier?
    let onSelect: (PersistentIdentifier) -> Void

    @Namespace private var selection

    var body: some View {
        Group {
            if children.count <= 3 {
                HStack(spacing: 4) {
                    ForEach(children) { child in
                        item(for: child, fillsWidth: true)
                    }
                }
                .padding(4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(children) { child in
                            item(for: child, fillsWidth: false)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .kidDoseGlass(in: Capsule())
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    private func item(for child: Child, fillsWidth: Bool) -> some View {
        let isSelected = child.persistentModelID == selectedID
        let childColor = Color(hex: child.colorHex)

        return Button {
            onSelect(child.persistentModelID)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(childColor.opacity(isSelected ? 0.95 : 0.22))
                    .frame(width: 26, height: 26)
                    .overlay {
                        Text(String(child.name.prefix(1)).uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                Text(child.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background {
                if isSelected {
                    Capsule()
                        .fill(childColor.opacity(0.18))
                        .overlay(Capsule().strokeBorder(childColor.opacity(0.55), lineWidth: 1))
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(child.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    let isWaitingForFamilyChildren: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isWaitingForFamilyChildren ? "arrow.triangle.2.circlepath.icloud" : "person.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, options: .repeating, isActive: isWaitingForFamilyChildren)
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
