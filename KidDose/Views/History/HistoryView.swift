import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \Child.name) private var children: [Child]
    @Query(sort: \DoseLog.timestamp, order: .reverse) private var allDoses: [DoseLog]
    @Environment(DoseViewModel.self) private var viewModel

    // nil = "All"
    @State private var selectedChildID: PersistentIdentifier? = nil

    private var filterOptions: [Child?] {
        [nil] + children
    }

    private var filteredDoses: [DoseLog] {
        guard let id = selectedChildID else { return allDoses }
        return allDoses.filter { $0.child?.persistentModelID == id }
    }

    private var filteredChildren: [Child]? {
        guard let id = selectedChildID else { return children }
        return children.filter { $0.persistentModelID == id }
    }

    private var statsMap: [String: Int] {
        var result: [String: Int] = [:]
        for med in Medication.allCases {
            result[med.displayName] = filteredDoses.filter { $0.medication == med.rawValue }.count
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Child filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            label: "All",
                            isSelected: selectedChildID == nil,
                            color: .accentColor
                        ) { selectedChildID = nil }

                        ForEach(children) { child in
                            FilterChip(
                                label: child.name,
                                isSelected: selectedChildID == child.persistentModelID,
                                color: Color(hex: child.colorHex)
                            ) { selectedChildID = child.persistentModelID }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(.systemBackground))

                Divider()

                // Stats summary
                StatsRowView(stats: statsMap)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))

                Divider()

                // Dose list
                if filteredDoses.isEmpty {
                    Spacer()
                    Text("No doses recorded")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List(filteredDoses) { dose in
                        DoseRowView(dose: dose)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? color.opacity(0.18) : Color(.tertiarySystemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? color : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stats Row

private struct StatsRowView: View {
    let stats: [String: Int]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Medication.allCases, id: \.rawValue) { med in
                HStack(spacing: 6) {
                    Image(systemName: med.iconName)
                        .foregroundStyle(med.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(med.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(stats[med.displayName] ?? 0) doses")
                            .font(.subheadline.bold())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Dose Row

private struct DoseRowView: View {
    let dose: DoseLog

    var medicationColor: Color {
        dose.medicationEnum?.color ?? .gray
    }

    var medicationIcon: String {
        dose.medicationEnum?.iconName ?? "pill"
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(medicationColor.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: medicationIcon)
                        .foregroundStyle(medicationColor)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(dose.child?.name ?? "Unknown")
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(dose.medication.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(medicationColor)
                }
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text(dose.givenBy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(dose.relativeTimestamp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}
