import SwiftUI
import SwiftData
import UIKit

// MARK: - HistoryView

struct HistoryView: View {
    @Query(sort: \Child.name) private var children: [Child]
    @Query(sort: \DoseLog.timestamp, order: .reverse) private var allDoses: [DoseLog]
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context

    @State private var showPast = true
    @State private var showUpcoming = false
    @State private var selectedChildID: PersistentIdentifier? = nil   // nil = All
    @State private var exportFile: ExportFile?
    @State private var exportErrorMessage: String?

    // MARK: Computed

    private var filteredDoses: [DoseLog] {
        guard let id = selectedChildID else { return allDoses }
        return allDoses.filter { $0.child?.persistentModelID == id }
    }

    private var filteredChildren: [Child] {
        guard let id = selectedChildID else { return Array(children) }
        return children.filter { $0.persistentModelID == id }
    }

    private var statsMap: [String: Int] {
        var result: [String: Int] = [:]
        for med in Medication.allCases {
            result[med.displayName] = filteredDoses.filter { $0.medication == med.rawValue }.count
        }
        return result
    }

    private var upcomingItems: [ScheduledDose] {
        viewModel.upcomingDoses(for: filteredChildren)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        HistoryModeToggleChip(
                            title: "Past",
                            systemImage: "clock.arrow.circlepath",
                            isOn: showPast,
                            color: .accentColor
                        ) {
                            togglePast()
                        }

                        HistoryModeToggleChip(
                            title: "Upcoming",
                            systemImage: "calendar.badge.clock",
                            isOn: showUpcoming,
                            color: .orange
                        ) {
                            toggleUpcoming()
                        }

                        Spacer()
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
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
                    }
                }
                .padding(10)
                .kidDoseCardSurface(cornerRadius: 13)
                .padding(.horizontal)

                contentArea
            }
            .padding(.top, 8)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportFullHistory()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(allDoses.isEmpty)
                }
            }
            .sheet(item: $exportFile) { file in
                ActivityShareSheet(activityItems: [file.url])
            }
            .alert(
                "Export history",
                isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented { exportErrorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "Could not export dose history.")
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        switch (showPast, showUpcoming) {
        case (true, false):
            pastContent
        case (false, true):
            upcomingContent
        case (true, true):
            combinedContent
        case (false, false):
            Spacer()
            Text("Select Past or Upcoming")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Past content

    @ViewBuilder
    private var pastContent: some View {
        StatsRowView(stats: statsMap)
            .padding(.horizontal)
            .padding(.bottom, 2)

        if filteredDoses.isEmpty {
            Spacer()
            Text("No doses recorded")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List {
                ForEach(filteredDoses) { dose in
                    DoseRowView(dose: dose)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onDelete(perform: deleteDoses)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    // MARK: Upcoming content

    @ViewBuilder
    private var upcomingContent: some View {
        if upcomingItems.isEmpty {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("All doses are ready now")
                    .font(.headline)
                Text("No upcoming dose windows to show.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            List(upcomingItems) { item in
                UpcomingHistoryRow(item: item)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    // MARK: Combined content

    @ViewBuilder
    private var combinedContent: some View {
        StatsRowView(stats: statsMap)
            .padding(.horizontal)
            .padding(.bottom, 2)

        List {
            Section("Upcoming") {
                if upcomingItems.isEmpty {
                    Text("No upcoming dose windows to show.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(upcomingItems) { item in
                        UpcomingHistoryRow(item: item)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }

            Section("Past") {
                if filteredDoses.isEmpty {
                    Text("No doses recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredDoses) { dose in
                        DoseRowView(dose: dose)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deleteDoses)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    // MARK: Toggle helpers

    private func togglePast() {
        if showPast && !showUpcoming { return }
        showPast.toggle()
    }

    private func toggleUpcoming() {
        if showUpcoming && !showPast { return }
        showUpcoming.toggle()
    }

    // MARK: Delete

    private func deleteDoses(at offsets: IndexSet) {
        let current = filteredDoses
        let targets: [DoseLog] = offsets.compactMap { index -> DoseLog? in
            guard current.indices.contains(index) else { return nil }
            return current[index]
        }
        for dose in targets {
            viewModel.deleteDose(dose, context: context)
        }
    }

    private func exportFullHistory() {
        guard !allDoses.isEmpty else {
            exportErrorMessage = "No dose history to export yet."
            return
        }

        do {
            let fileURL = try writeFullHistoryCSV()
            exportFile = ExportFile(url: fileURL)
        } catch {
            exportErrorMessage = "Could not create CSV export: \(error.localizedDescription)"
        }
    }

    private func writeFullHistoryCSV() throws -> URL {
        let sortedDoses = allDoses.sorted { $0.timestamp < $1.timestamp }

        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"

        var rows: [String] = []
        rows.append(
            [
                "child_name",
                "medication",
                "dose_timestamp_iso8601",
                "dose_timestamp_local",
                "given_by",
                "interval_hours",
                "dose_note"
            ].joined(separator: ",")
        )

        for dose in sortedDoses {
            let childName = dose.child?.name ?? "Unknown"
            let medication = dose.medicationEnum?.displayName ?? dose.medication.capitalized
            let isoTimestamp = timestampFormatter.string(from: dose.timestamp)
            let localTimestamp = localFormatter.string(from: dose.timestamp)
            let interval = dose.usedIntervalHours > 0
                ? dose.usedIntervalHours
                : (dose.medicationEnum?.intervalHours ?? 0)
            let intervalString = formatIntervalHours(interval)
            let note = dose.medicationEnum.flatMap { med in
                dose.child?.doseNote(for: med)
            } ?? ""

            let row = [
                csvEscape(childName),
                csvEscape(medication),
                csvEscape(isoTimestamp),
                csvEscape(localTimestamp),
                csvEscape(dose.givenBy),
                csvEscape(intervalString),
                csvEscape(note)
            ].joined(separator: ",")
            rows.append(row)
        }

        let csv = rows.joined(separator: "\n")
        let fileName = "KidDose-History-\(exportTimestamp()).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func formatIntervalHours(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(value)
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}

private struct HistoryModeToggleChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, KidDoseLayout.compactHorizontalPadding)
            .padding(.vertical, KidDoseLayout.compactVerticalPadding)
            .foregroundStyle(isOn ? color : .secondary)
            .background(
                isOn ? color.opacity(0.16) : Color(.tertiarySystemBackground),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isOn ? color : Color.clear, lineWidth: 1.3)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Upcoming History Row

private struct UpcomingHistoryRow: View {
    let item: ScheduledDose

    var body: some View {
        HStack(spacing: 10) {
            // Medication badge
            Circle()
                .fill(item.medication.color.opacity(0.15))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: item.medication.iconName)
                        .foregroundStyle(item.medication.color)
                }

            VStack(alignment: .leading, spacing: 3) {
                // Child · Medication
                HStack {
                    Text(item.child.name)
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(item.medication.displayName)
                        .font(.subheadline)
                        .foregroundStyle(item.medication.color)
                }
                // Absolute time label
                Text(formattedAbsoluteTime(item.nextDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Live countdown updating every minute
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let remaining = item.nextDate.timeIntervalSince(context.date)
                if remaining > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(roughCountdown(remaining))
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundStyle(item.medication.color)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .kidDoseSubtleSurface(cornerRadius: 12)
    }

    private func formattedAbsoluteTime(_ date: Date) -> String {
        let cal = Calendar.current
        let tf = DateFormatter()
        tf.timeStyle = .short
        tf.dateStyle = .none
        let timeStr = tf.string(from: date)

        if cal.isDateInToday(date)    { return "Today at \(timeStr)" }
        if cal.isDateInTomorrow(date) { return "Tomorrow at \(timeStr)" }
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        return "\(df.string(from: date)) at \(timeStr)"
    }

    private func roughCountdown(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
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
                .padding(.horizontal, KidDoseLayout.compactHorizontalPadding)
                .padding(.vertical, KidDoseLayout.compactVerticalPadding)
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
        HStack(spacing: 8) {
            ForEach(Medication.allCases, id: \.rawValue) { med in
                HStack(spacing: 5) {
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
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .kidDoseSubtleSurface(cornerRadius: 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .kidDoseCardSurface(cornerRadius: 13)
    }
}

// MARK: - Dose Row (Past)

private struct DoseRowView: View {
    let dose: DoseLog

    var medicationColor: Color { dose.medicationEnum?.color ?? .gray }
    var medicationIcon: String { dose.medicationEnum?.iconName ?? "pill" }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(medicationColor.opacity(0.15))
                .frame(width: 38, height: 38)
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
                    // Show which interval was used if it differs from the default
                    if let med = dose.medicationEnum,
                       dose.usedIntervalHours > 0,
                       dose.usedIntervalHours != med.intervalHours {
                        Text("· \(Int(dose.usedIntervalHours))h interval")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(relativeTimestamp(for: dose.timestamp, now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .kidDoseSubtleSurface(cornerRadius: 12)
    }

    private func relativeTimestamp(for timestamp: Date, now: Date) -> String {
        let delta = now.timeIntervalSince(timestamp)
        if abs(delta) < 30 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: now)
    }
}
