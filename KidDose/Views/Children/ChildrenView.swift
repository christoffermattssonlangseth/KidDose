import SwiftUI
import SwiftData

struct ChildrenView: View {
    @Environment(\.modelContext) private var context
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(AppLockService.self) private var appLock
    @Query(sort: \Child.name) private var children: [Child]

    @State private var showAddChild = false
    @State private var showDeleteConfirm = false
    @State private var childToDelete: Child?
    @State private var isFamilyActionInProgress = false
    @State private var inviteURL: URL?
    @State private var inviteLinkText = ""
    @State private var familyStatusMessage: String?
    @State private var familyErrorMessage: String?
    @State private var isManualSyncInProgress = false
    @State private var lastManualSyncAt: Date?
    @State private var manualSyncStatus: String?
    @State private var manualSyncError: String?
    @State private var isLiveActivityRefreshing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    SettingsInfoText("This tab is for setup. Dose logs and exports are in the History tab.")
                }

                Section {
                    if children.isEmpty {
                        ContentUnavailableView(
                            "No children",
                            systemImage: "person.2",
                            description: Text("Add your first child profile to start tracking doses.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(children) { child in
                            ChildRowView(child: child)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: confirmDelete)
                    }

                    Button {
                        showAddChild = true
                    } label: {
                        SettingsActionLabel(
                            title: "Add Child",
                            systemImage: "plus.circle.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } header: {
                    Text("Children")
                } footer: {
                    Text("Swipe left on a child to delete the profile and its dose data.")
                }

                Section("Family Sharing") {
                    sharingButton
                }

                Section("Live Activity") {
                    SettingsStatusRow(
                        title: "Device status",
                        value: viewModel.liveActivitiesEnabledOnDevice ? "Enabled" : "Disabled",
                        color: viewModel.liveActivitiesEnabledOnDevice ? .green : .orange
                    )

                    SettingsGroupHeader("When to show")

                    Picker(
                        "Show",
                        selection: Binding(
                            get: { viewModel.liveActivityDisplayMode },
                            set: { viewModel.setLiveActivityDisplayMode($0, context: context) }
                        )
                    ) {
                        ForEach(LiveActivityDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.liveActivityDisplayMode == .thirtyMinutesBefore {
                        SettingsGroupHeader("Due soon threshold")
                        Picker(
                            "Threshold",
                            selection: Binding(
                                get: { viewModel.liveActivityDueSoonThreshold },
                                set: { viewModel.setLiveActivityDueSoonThreshold($0, context: context) }
                            )
                        ) {
                            ForEach(LiveActivityDueSoonThreshold.allCases) { threshold in
                                Text(threshold.title).tag(threshold)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    SettingsGroupHeader("Appearance")
                    Picker(
                        "Layout",
                        selection: Binding(
                            get: { viewModel.liveActivityLayoutStyle },
                            set: { viewModel.setLiveActivityLayoutStyle($0, context: context) }
                        )
                    ) {
                        ForEach(LiveActivityLayoutStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(
                        "Larger countdown text",
                        isOn: Binding(
                            get: { viewModel.liveActivityPreferLargeText },
                            set: { viewModel.setLiveActivityPreferLargeText($0, context: context) }
                        )
                    )

                    SettingsGroupHeader("Actions")
                    Button {
                        Task {
                            isLiveActivityRefreshing = true
                            viewModel.refreshLiveActivity(context: context)
                            try? await Task.sleep(for: .milliseconds(700))
                            isLiveActivityRefreshing = false
                        }
                    } label: {
                        SettingsActionLabel(
                            title: isLiveActivityRefreshing ? "Refreshing..." : "Update Live Activity",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLiveActivityRefreshing)

                    if let refreshedAt = viewModel.liveActivityLastRefreshAt {
                        SettingsInfoText("Last refresh: \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                    }

                    SettingsInfoText(viewModel.liveActivityStatusMessage)

                    if let liveActivityError = viewModel.liveActivityErrorMessage {
                        SettingsInfoText(liveActivityError)
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
                        SettingsInfoText("KidDose will lock when it leaves the foreground.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddChild) {
                AddChildSheet()
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

    // MARK: - Settings Panel

    @ViewBuilder
    private var sharingButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.iCloudAvailable {
                SettingsInfoText("Family sharing needs iCloud + CloudKit capability. Personal Team signing disables this.")
            } else if !FamilyCloudSyncService.shared.isConfigured {
                SettingsInfoText("Set a real bundle identifier to enable family sharing.")
            }

            if viewModel.familySyncEnabled {
                SettingsGroupHeader("Connection")
                HStack {
                    FamilyStatusPill(title: "Connected", systemImage: "checkmark.circle.fill", color: .green)
                    Spacer()
                    Text(viewModel.familySyncOwner ? "Owner" : "Participant")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                }

                if let familyID = viewModel.familyIdentifier {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Family ID")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(familyID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .kidDoseSubtleSurface(cornerRadius: 10)
                }

                if viewModel.familySyncOwner, let currentInviteURL = inviteURL ?? viewModel.familyInviteURL {
                    SettingsGroupHeader("Invite partner")
                    ShareLink(
                        item: currentInviteURL,
                        preview: SharePreview("KidDose Family Invite")
                    ) {
                        SettingsActionLabel(
                            title: "Share Invite Link",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                SettingsGroupHeader("Sync")
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
                    SettingsActionLabel(
                        title: isManualSyncInProgress ? "Syncing..." : "Sync Now",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(
                    isManualSyncInProgress
                        || !FamilyCloudSyncService.shared.isConfigured
                )

                if let lastManualSyncAt {
                    SettingsInfoText("Last sync: \(lastManualSyncAt.formatted(date: .omitted, time: .shortened))")
                }

                if let manualSyncStatus {
                    SettingsInfoText(manualSyncStatus)
                }

                if let manualSyncError {
                    SettingsInfoText(manualSyncError)
                }

                Button(role: .destructive) {
                    viewModel.clearFamilySync()
                    inviteURL = nil
                    inviteLinkText = ""
                    familyStatusMessage = nil
                    familyErrorMessage = nil
                    lastManualSyncAt = nil
                    manualSyncStatus = nil
                    manualSyncError = nil
                } label: {
                    SettingsActionLabel(
                        title: "Disconnect Family Sharing",
                        systemImage: "person.2.slash"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                SettingsGroupHeader("Connection")
                FamilyStatusPill(title: "Not connected", systemImage: "person.2", color: .secondary)

                SettingsGroupHeader("Create family")
                Button {
                    isFamilyActionInProgress = true
                    Task {
                        inviteURL = await viewModel.createSecureFamilyInvite(context: context)
                        familyStatusMessage = viewModel.familySyncLastStatusMessage
                        familyErrorMessage = viewModel.familySyncLastErrorMessage
                        isFamilyActionInProgress = false
                    }
                } label: {
                    SettingsActionLabel(
                        title: "Create Family & Invite",
                        systemImage: "person.2.badge.plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!viewModel.familySyncAvailable || isFamilyActionInProgress)

                SettingsGroupHeader("Join family")
                VStack(alignment: .leading, spacing: 8) {
                    SettingsInfoText("Paste the invite link from your partner.")
                    TextField("Paste invite link", text: $inviteLinkText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    isFamilyActionInProgress = true
                    let trimmed = inviteLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        guard let url = URL(string: trimmed) else {
                            familyErrorMessage = "Invalid invite link."
                            familyStatusMessage = nil
                            isFamilyActionInProgress = false
                            return
                        }

                        let accepted = await viewModel.acceptCloudShareURL(url, context: context)
                        familyStatusMessage = viewModel.familySyncLastStatusMessage
                        if accepted {
                            familyErrorMessage = viewModel.familySyncLastErrorMessage
                            inviteLinkText = ""
                        } else {
                            familyErrorMessage = viewModel.familySyncLastErrorMessage
                                ?? "Could not accept invite link."
                        }
                        isFamilyActionInProgress = false
                    }
                } label: {
                    SettingsActionLabel(
                        title: "Accept Invite Link",
                        systemImage: "checkmark.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    isFamilyActionInProgress
                        || !viewModel.familySyncAvailable
                        || inviteLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button {
                    isFamilyActionInProgress = true
                    Task {
                        let joined = await viewModel.refreshAcceptedFamily(context: context)
                        familyStatusMessage = viewModel.familySyncLastStatusMessage
                        if joined {
                            familyErrorMessage = viewModel.familySyncLastErrorMessage
                        } else {
                            familyErrorMessage = viewModel.familySyncLastErrorMessage
                                ?? "No accepted invite found yet."
                        }
                        isFamilyActionInProgress = false
                    }
                } label: {
                    SettingsActionLabel(
                        title: "Refresh Accepted Invite",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isFamilyActionInProgress || !viewModel.familySyncAvailable)

                if let familyStatusMessage {
                    SettingsInfoText(familyStatusMessage)
                }

                if let familyErrorMessage {
                    SettingsInfoText(familyErrorMessage)
                        .textSelection(.enabled)
                }
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

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    Color(hex: child.colorHex)
                        .shadow(.inner(color: .black.opacity(0.18), radius: 3, x: 0, y: 2))
                )
                .frame(width: 44, height: 44)
                .overlay {
                    Text(child.name.prefix(1).uppercased())
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(child.name)
                    .font(.headline)
                Text("Profile used in Home and History")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .kidDoseSubtleSurface(cornerRadius: 11)
    }
}

private struct SettingsActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, KidDoseLayout.compactVerticalPadding)
            .font(.subheadline.weight(.semibold))
    }
}

private struct SettingsInfoText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct SettingsGroupHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        }
    }
}

private struct FamilyStatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
