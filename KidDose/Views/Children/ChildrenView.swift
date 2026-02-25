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
    @State private var isManualSyncInProgress = false
    @State private var lastManualSyncAt: Date?
    @State private var manualSyncStatus: String?
    @State private var manualSyncError: String?

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
            if viewModel.familySyncEnabled {
                HStack {
                    Text("Secure family sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.familySyncOwner ? "Owner" : "Participant")
                        .font(.caption.monospacedDigit().bold())
                }

                if let familyID = viewModel.familyIdentifier {
                    Text(familyID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if viewModel.familySyncOwner, let inviteURL = viewModel.familyInviteURL {
                    ShareLink(
                        item: inviteURL,
                        preview: SharePreview("KidDose Family Invite")
                    ) {
                        Label("Invite Parent", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                }
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
                        isManualSyncInProgress = true
                        let success = await viewModel.runManualFamilySync(context: context)
                        isManualSyncInProgress = false
                        if success {
                            lastManualSyncAt = .now
                            manualSyncStatus = viewModel.familySyncLastStatusMessage ?? "Sync completed."
                            manualSyncError = viewModel.familySyncLastErrorMessage
                        } else {
                            manualSyncStatus = viewModel.familySyncLastStatusMessage
                            manualSyncError = viewModel.familySyncLastErrorMessage
                                ?? "Sync unavailable. Check iCloud sign-in and family setup."
                        }
                    }
                } label: {
                    Label(
                        isManualSyncInProgress ? "Syncing..." : "Sync Now",
                        systemImage: "arrow.clockwise"
                    )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(
                    isManualSyncInProgress
                        || !viewModel.familySyncEnabled
                        || !FamilyCloudSyncService.shared.isConfigured
                )

                if let lastManualSyncAt {
                    Text("Last sync: \(lastManualSyncAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let manualSyncStatus {
                    Text(manualSyncStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let manualSyncError {
                    Text(manualSyncError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.iCloudAvailable {
                Text("Family sync needs iCloud + CloudKit capability. Personal Team signing disables this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !FamilyCloudSyncService.shared.isConfigured {
                Text("Set a real bundle identifier to enable family sync.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            #if DEBUG
            VStack(alignment: .leading, spacing: 4) {
                Text("Bundle: \(viewModel.bundleIdentifier)")
                Text("Container: \(viewModel.cloudContainerIdentifier)")
                Text("iCloud account: \(viewModel.iCloudAvailable ? "available" : "unavailable")")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            #endif
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
    @Environment(AppLockService.self) private var appLock
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var inviteURL: URL?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if !viewModel.familySyncAvailable {
                    Section {
                        Text("Family sync requires iCloud + CloudKit capability. On a Personal Team, build works locally but family sync is unavailable.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Create secure family") {
                    Button("Create Family & Invite") {
                        isWorking = true
                        Task {
                            inviteURL = await viewModel.createSecureFamilyInvite(context: context)
                            statusMessage = viewModel.familySyncLastStatusMessage
                            errorMessage = viewModel.familySyncLastErrorMessage
                            isWorking = false
                        }
                    }
                    .disabled(!viewModel.familySyncAvailable || isWorking)
                }

                if viewModel.familySyncOwner, let inviteURL = inviteURL ?? viewModel.familyInviteURL {
                    Section("Invite partner") {
                        ShareLink(
                            item: inviteURL,
                            preview: SharePreview("KidDose Family Invite")
                        ) {
                            Label("Share Invite Link", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("Join partner family") {
                    Text("Ask your partner to send the CloudKit invite link. After accepting it, tap refresh below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Refresh Accepted Invite") {
                        isWorking = true
                        Task {
                            let joined = await viewModel.refreshAcceptedFamily(context: context)
                            statusMessage = viewModel.familySyncLastStatusMessage
                            if joined {
                                errorMessage = viewModel.familySyncLastErrorMessage
                            } else {
                                errorMessage = viewModel.familySyncLastErrorMessage
                                    ?? "No accepted invite found yet."
                            }
                            isWorking = false
                        }
                    }
                    .disabled(
                        isWorking
                            || !viewModel.familySyncAvailable
                    )
                }

                if viewModel.familySyncEnabled {
                    Section {
                        Button("Disconnect Family Sync", role: .destructive) {
                            viewModel.clearFamilySync()
                            statusMessage = nil
                            errorMessage = nil
                            inviteURL = nil
                        }
                    }
                }

                if let statusMessage {
                    Section("Last sync result") {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section("Last sync error") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("Privacy") {
                    Toggle(
                        "Require Face ID / Passcode",
                        isOn: Binding(
                            get: { appLock.isEnabled },
                            set: { appLock.setEnabled($0) }
                        )
                    )

                    if appLock.isEnabled {
                        Text("KidDose will lock when it leaves the foreground.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
