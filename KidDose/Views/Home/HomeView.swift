import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(DoseViewModel.self) private var viewModel
    @Query(sort: \Child.name) private var children: [Child]

    @State private var selectedChildID: PersistentIdentifier?

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
                        // Child selector
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
                        // Single child: no selector needed

                        // Medication cards
                        if let child = selectedChild {
                            VStack(spacing: 16) {
                                ForEach(Medication.allCases, id: \.rawValue) { med in
                                    MedicationCard(medication: med, child: child)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("KidDose")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                // Ensure selection stays valid when children list changes.
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
