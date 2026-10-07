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

    private var visibleChildren: [Child] {
        viewModel.visibleChildrenForCurrentFamily(children)
    }

    private var isWaitingForFamilyChildren: Bool {
        viewModel.familySyncEnabled && !viewModel.familySyncOwner && visibleChildren.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                childrenSection
                familySharingSection
                liveActivitySection
                privacySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddChild) { AddChildSheet() }
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
            .task { await viewModel.syncFamilyCloud(context: context) }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var overviewSection: some View {
        Section("Overview") {
            SettingsInfoText("This tab is for setup. Dose logs and exports are in the History tab.")
        }
    }

    @ViewBuilder
    private var childrenSection: some View {
        Section {
            if visibleChildren.isEmpty {
                ContentUnavailableView(
                    isWaitingForFamilyChildren ? "Waiting for shared children" : "No children",
                    systemImage: "person.2",
                    description: Text(
                        isWaitingForFamilyChildren
                            ? "Family sharing is connected. Run Sync Now to fetch shared data."
                            : "Add your first child profile to start tracking doses."
                    )
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(visibleChildren) { child in
                    ChildRowView(child: child)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onDelete(perform: confirmDelete)
            }

            Button { showAddChild = true } label: {
                SettingsActionLabel(title: "Add Child", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } header: {
            Text("Children")
        } footer: {
            Text("Swipe left on a child to delete the profile and its dose data.")
        }
    }

    @ViewBuilder
    private var familySharingSection: some View {
        Section("Family Sharing") { sharingButton }
    }

    @ViewBuilder
    private var liveActivitySection: some View {
        Section {
            SettingsStatusRow(
                title: "Device status",
                value: viewModel.liveActivitiesEnabledOnDevice ? "Enabled" : "Disabled",
                color: viewModel.liveActivitiesEnabledOnDevice ? .green : .orange
            )

            SettingsGroupHeader("When to show")
            liveActivityDisplayModePicker

            if viewModel.liveActivityDisplayMode == .thirtyMinutesBefore {
                SettingsGroupHeader("Due soon threshold")
                liveActivityThresholdPicker
            }

            SettingsGroupHeader("Appearance")
            liveActivityLayoutPicker
            liveActivityLargeTextToggle

            SettingsGroupHeader("Actions")
            liveActivityRefreshButton

            if let refreshedAt = viewModel.liveActivityLastRefreshAt {
                SettingsInfoText("Last refresh: \(refreshedAt.formatted(date: .omitted, time: .shortened))")
            }
            SettingsInfoText(viewModel.liveActivityStatusMessage)
            if let liveActivityError = viewModel.liveActivityErrorMessage {
                SettingsInfoText(liveActivityError).textSelection(.enabled)
            }
        } header: {
            Text("Live Activity")
        } footer: {
            Text("Shows the next dose on the Lock Screen and in the Dynamic Island. iOS ends a Live Activity after 8 hours; KidDose starts a new one the next time you open the app. You can also add KidDose widgets to the Lock Screen from Settings → Wallpaper → Customize.")
        }
    }

    @ViewBuilder
    private var privacySection: some View {
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

    // MARK: - Live Activity controls

    @ViewBuilder
    private var liveActivityDisplayModePicker: some View {
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
    }

    @ViewBuilder
    private var liveActivityThresholdPicker: some View {
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

    @ViewBuilder
    private var liveActivityLayoutPicker: some View {
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
    }

    @ViewBuilder
    private var liveActivityLargeTextToggle: some View {
        Toggle(
            "Larger countdown text",
            isOn: Binding(
                get: { viewModel.liveActivityPreferLargeText },
                set: { viewModel.setLiveActivityPreferLargeText($0, context: context) }
            )
        )
    }

    @ViewBuilder
    private var liveActivityRefreshButton: some View {
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
    }

    // MARK: - Settings Panel

    @ViewBuilder
    private var sharingButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            familyAvailabilityWarning
            if viewModel.familySyncEnabled {
                familyConnectedView
            } else {
                familyNotConnectedView
            }
            #if DEBUG
            debugInfoView
            #endif
        }
    }

    @ViewBuilder
    private var familyAvailabilityWarning: some View {
        if !viewModel.iCloudAvailable {
            SettingsInfoText("Family sharing needs iCloud + CloudKit capability. Personal Team signing disables this.")
        } else if !FamilyCloudSyncService.shared.isConfigured {
            SettingsInfoText("Set a real bundle identifier to enable family sharing.")
        }
    }

    @ViewBuilder
    private var familyConnectedView: some View {
        SettingsGroupHeader("Connection")
        connectionRow
        familyIDBlock
        if viewModel.familySyncOwner { inviteShareBlock }
        SettingsGroupHeader("Sync")
        syncNowButton
        syncStatusBlock
        disconnectButton
    }

    @ViewBuilder
    private var connectionRow: some View {
        HStack {
            PillChip(
                text: "Connected",
                systemImage: "checkmark.circle.fill",
                tone: .ready,
                style: .tintedText
            )
            Spacer()
            Text(viewModel.familySyncOwner ? "Owner" : "Participant")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var familyIDBlock: some View {
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
    }

    @ViewBuilder
    private var inviteShareBlock: some View {
        if let currentInviteURL = inviteURL ?? viewModel.familyInviteURL {
            SettingsGroupHeader("Invite partner")
            ShareLink(item: currentInviteURL, preview: SharePreview("KidDose Family Invite")) {
                SettingsActionLabel(title: "Share Invite Link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var syncNowButton: some View {
        Button {
            Task { await performManualSync() }
        } label: {
            SettingsActionLabel(
                title: isManualSyncInProgress ? "Syncing..." : "Sync Now",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isManualSyncInProgress || !FamilyCloudSyncService.shared.isConfigured)
    }

    @ViewBuilder
    private var syncStatusBlock: some View {
        if let lastManualSyncAt {
            SettingsInfoText("Last sync: \(lastManualSyncAt.formatted(date: .omitted, time: .shortened))")
        }
        if let manualSyncStatus { SettingsInfoText(manualSyncStatus) }
        if let manualSyncError { SettingsInfoText(manualSyncError) }
    }

    @ViewBuilder
    private var disconnectButton: some View {
        Button(role: .destructive) {
            resetFamilyState()
        } label: {
            SettingsActionLabel(title: "Disconnect Family Sharing", systemImage: "person.2.slash")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private var familyNotConnectedView: some View {
        SettingsGroupHeader("Connection")
        PillChip(
            text: "Not connected",
            systemImage: "person.2",
            tone: .neutral,
            style: .tintedText
        )

        SettingsGroupHeader("Create family")
        createFamilyButton

        SettingsGroupHeader("Join family")
        joinFamilyInputRow
        acceptInviteButton
        refreshAcceptedInviteButton
        familyJoinStatusBlock
    }

    @ViewBuilder
    private var createFamilyButton: some View {
        Button {
            Task { await performCreateFamily() }
        } label: {
            SettingsActionLabel(title: "Create Family & Invite", systemImage: "person.2.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!viewModel.familySyncAvailable || isFamilyActionInProgress)
    }

    @ViewBuilder
    private var joinFamilyInputRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsInfoText("Paste the invite link from your partner.")
            TextField("Paste invite link", text: $inviteLinkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var acceptInviteButton: some View {
        Button {
            Task { await performAcceptInvite() }
        } label: {
            SettingsActionLabel(title: "Accept Invite Link", systemImage: "checkmark.circle")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(
            isFamilyActionInProgress
                || !viewModel.familySyncAvailable
                || inviteLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    @ViewBuilder
    private var refreshAcceptedInviteButton: some View {
        Button {
            Task { await performRefreshAcceptedFamily() }
        } label: {
            SettingsActionLabel(title: "Refresh Accepted Invite", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isFamilyActionInProgress || !viewModel.familySyncAvailable)
    }

    @ViewBuilder
    private var familyJoinStatusBlock: some View {
        if let familyStatusMessage { SettingsInfoText(familyStatusMessage) }
        if let familyErrorMessage {
            SettingsInfoText(familyErrorMessage).textSelection(.enabled)
        }
    }

    #if DEBUG
    @ViewBuilder
    private var debugInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bundle: \(viewModel.bundleIdentifier)")
            Text("Container: \(viewModel.cloudContainerIdentifier)")
            Text("iCloud account: \(viewModel.iCloudAvailable ? "available" : "unavailable")")
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
    }
    #endif

    // MARK: - Actions

    private func performManualSync() async {
        isManualSyncInProgress = true
        manualSyncStatus = nil
        manualSyncError = nil
        let syncTask = Task { await viewModel.runManualFamilySync(context: context) }
        let immediateResult = await waitForManualSyncResult(from: syncTask, timeoutSeconds: 25)

        if let success = immediateResult {
            isManualSyncInProgress = false
            applyManualSyncResult(success: success)
            return
        }

        // Soft timeout: keep the sync task running in background; update UI now.
        isManualSyncInProgress = false
        manualSyncStatus = "Sync is taking longer than usual. It will finish in the background."
        manualSyncError = nil

        let success = await syncTask.value
        applyManualSyncResult(success: success)
    }

    private func applyManualSyncResult(success: Bool) {
        if success {
            lastManualSyncAt = .now
            manualSyncStatus = viewModel.familySyncLastStatusMessage ?? "Sync completed."
            manualSyncError = viewModel.familySyncLastErrorMessage
        } else {
            manualSyncStatus = viewModel.familySyncLastStatusMessage
            manualSyncError = viewModel.familySyncLastErrorMessage
                ?? viewModel.familySyncLastStatusMessage
                ?? "Sync unavailable. Check iCloud sign-in and family setup."
        }
    }

    private func performCreateFamily() async {
        isFamilyActionInProgress = true
        inviteURL = await viewModel.createSecureFamilyInvite(context: context)
        familyStatusMessage = viewModel.familySyncLastStatusMessage
        familyErrorMessage = viewModel.familySyncLastErrorMessage
        isFamilyActionInProgress = false
    }

    private func performAcceptInvite() async {
        isFamilyActionInProgress = true
        defer { isFamilyActionInProgress = false }

        let trimmed = inviteLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            familyErrorMessage = "Invalid invite link."
            familyStatusMessage = nil
            return
        }

        let accepted = await viewModel.acceptCloudShareURL(url, context: context)
        familyStatusMessage = viewModel.familySyncLastStatusMessage
        if accepted {
            familyErrorMessage = viewModel.familySyncLastErrorMessage
            inviteLinkText = ""
        } else {
            familyErrorMessage = viewModel.familySyncLastErrorMessage ?? "Could not accept invite link."
        }
    }

    private func performRefreshAcceptedFamily() async {
        isFamilyActionInProgress = true
        defer { isFamilyActionInProgress = false }
        let joined = await viewModel.refreshAcceptedFamily(context: context)
        familyStatusMessage = viewModel.familySyncLastStatusMessage
        if joined {
            familyErrorMessage = viewModel.familySyncLastErrorMessage
        } else {
            familyErrorMessage = viewModel.familySyncLastErrorMessage ?? "No accepted invite found yet."
        }
    }

    private func resetFamilyState() {
        viewModel.clearFamilySync()
        inviteURL = nil
        inviteLinkText = ""
        familyStatusMessage = nil
        familyErrorMessage = nil
        lastManualSyncAt = nil
        manualSyncStatus = nil
        manualSyncError = nil
    }

    // MARK: - Delete

    private func confirmDelete(at offsets: IndexSet) {
        if let index = offsets.first {
            guard visibleChildren.indices.contains(index) else { return }
            childToDelete = visibleChildren[index]
            showDeleteConfirm = true
        }
    }

    private func waitForManualSyncResult(
        from syncTask: Task<Bool, Never>,
        timeoutSeconds: Double = 25
    ) async -> Bool? {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                await syncTask.value
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
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
                    child.tintColor
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

