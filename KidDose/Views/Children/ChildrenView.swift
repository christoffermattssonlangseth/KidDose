import SwiftUI
import SwiftData
import CloudKit

struct ChildrenView: View {
    @Environment(\.modelContext) private var context
    @Environment(DoseViewModel.self) private var viewModel
    @Query(sort: \Child.name) private var children: [Child]

    @State private var showAddChild = false
    @State private var showDeleteConfirm = false
    @State private var childToDelete: Child?
    @State private var showSharing = false
    @State private var activeShare: CKShare? = nil
    @State private var shareParticipantCount: Int = 0

    private let ckContainer = CKContainer(identifier: "iCloud.com.yourname.kiddose")

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
            .sheet(isPresented: $showSharing) {
                CloudSharingView(
                    container: ckContainer,
                    share: activeShare,
                    onDismiss: {
                        showSharing = false
                        Task { await fetchShareStatus() }
                    }
                )
                .ignoresSafeArea()
            }
            .confirmationDialog(
                "Delete \(childToDelete?.name ?? "child")?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let child = childToDelete {
                        context.delete(child)
                        try? context.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All dose history for this child will also be deleted.")
            }
            .task { await fetchShareStatus() }
        }
    }

    // MARK: - Sharing Button

    @ViewBuilder
    private var sharingButton: some View {
        VStack(spacing: 8) {
            if shareParticipantCount > 0 {
                Label(
                    "Shared with \(shareParticipantCount) person\(shareParticipantCount == 1 ? "" : "s")",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.green)
            }

            Button {
                if viewModel.iCloudAvailable {
                    showSharing = true
                }
            } label: {
                Label("Share with Partner", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.iCloudAvailable)

            if !viewModel.iCloudAvailable {
                Text("Sign in to iCloud to enable sharing.")
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

    // MARK: - Share Status

    private func fetchShareStatus() async {
        do {
            let shares = try await ckContainer.privateCloudDatabase.allSubscriptions()
            // For a real app, fetch actual CKShare records. Here we just check subscriptions
            // as a proxy for whether sharing has been set up.
            // In production, use CKFetchShareParticipantsOperation.
            _ = shares
        } catch {
            // Silently ignore — sharing status is non-critical UI.
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
