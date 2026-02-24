import SwiftUI
import SwiftData

struct ChildrenView: View {
    @Environment(\.modelContext) private var context
    @Environment(DoseViewModel.self) private var viewModel
    @Query(sort: \Child.name) private var children: [Child]

    @State private var showAddChild = false
    @State private var showDeleteConfirm = false
    @State private var childToDelete: Child?
    @State private var showFamilySetup = false

    private var canUseFamilySync: Bool {
        viewModel.familySyncAvailable
    }

    var body: some View {
        NavigationStack {
            List {
                if children.isEmpty {
                    ContentUnavailableView(
                        "No children",
                        systemImage: "person.2",
                        description: Text("Tap + to add your first child.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(children) { child in
                        ChildRowView(child: child)
                    }
                    .onDelete(perform: confirmDelete)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Children")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddChild = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                sharingButton
                    .padding()
                    .background(.ultraThinMaterial)
            }
            .sheet(isPresented: $showAddChild) {
                AddChildSheet()
            }
            .sheet(isPresented: $showFamilySetup) {
                FamilySetupSheet()
            }
            .confirmationDialog(
                "Delete \(childToDelete?.name ?? "child")?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let child = childToDelete {
                        viewModel.deleteChild(child, context: context)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All dose history for this child will also be deleted.")
            }
            .task {
                await viewModel.syncFamilyCloud(context: context)
            }
        }
    }

    // MARK: - Family Sync Panel

    @ViewBuilder
    private var sharingButton: some View {
        VStack(spacing: 8) {
            if let familyCode = viewModel.familyCode {
                HStack {
                    Text("Family code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(familyCode)
                        .font(.caption.monospacedDigit().bold())
                }

                ShareLink(
                    item: "Join our KidDose family using code: \(familyCode)",
                    preview: SharePreview("KidDose Family Code")
                ) {
                    Label("Share Code", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .font(.headline)
                }
                .buttonStyle(.bordered)
            }

            Button {
                showFamilySetup = true
            } label: {
                Label(
                    viewModel.familySyncEnabled ? "Manage Family Sync" : "Set Up Family Sync",
                    systemImage: "person.2.badge.gearshape"
                )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canUseFamilySync)

            if viewModel.familySyncEnabled {
                Button {
                    Task {
                        await viewModel.syncFamilyCloud(context: context)
                    }
                } label: {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(!canUseFamilySync)
            }

            if !viewModel.iCloudAvailable {
                Text("Sign in to iCloud to enable family sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !FamilyCloudSyncService.shared.isConfigured {
                Text("Set a real bundle identifier to enable family sync.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Delete

    private func confirmDelete(at offsets: IndexSet) {
        if let index = offsets.first {
            childToDelete = children[index]
            showDeleteConfirm = true
        }
    }
}

// MARK: - Child Row

private struct ChildRowView: View {
    let child: Child

    var totalDoses: Int { child.doses.count }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color(hex: child.colorHex))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(child.name.prefix(1).uppercased())
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(child.name)
                    .font(.headline)
                Text("\(totalDoses) dose\(totalDoses == 1 ? "" : "s") total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Per-medication mini summary
            HStack(spacing: 10) {
                ForEach(Medication.allCases, id: \.rawValue) { med in
                    let count = child.doses.filter { $0.medication == med.rawValue }.count
                    VStack(spacing: 2) {
                        Image(systemName: med.iconName)
                            .foregroundStyle(med.color)
                            .imageScale(.small)
                        Text("\(count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FamilySetupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var joinCode: String = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                if !viewModel.familySyncAvailable {
                    Section {
                        Text("Sign in to iCloud and configure a real bundle identifier to enable family sync.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Create a new family") {
                    Button("Create Family Code") {
                        isWorking = true
                        Task {
                            _ = await viewModel.createFamilyCode(context: context)
                            isWorking = false
                        }
                    }
                    .disabled(!viewModel.familySyncAvailable || isWorking)

                    if let code = viewModel.familyCode {
                        LabeledContent("Current code", value: code)
                            .font(.caption.monospacedDigit())
                    }
                }

                Section("Join with a code") {
                    TextField("Enter code", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Join Family") {
                        isWorking = true
                        Task {
                            _ = await viewModel.joinFamily(code: joinCode, context: context)
                            isWorking = false
                        }
                    }
                    .disabled(
                        joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isWorking
                            || !viewModel.familySyncAvailable
                    )
                }

                if viewModel.familySyncEnabled {
                    Section {
                        Button("Stop Family Sync", role: .destructive) {
                            viewModel.clearFamilyCode()
                        }
                    }
                }
            }
            .navigationTitle("Family Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
