import SwiftUI
import SwiftData
import UIKit

// MARK: - HistoryView

struct HistoryView: View {
    @Query(sort: \Child.name) private var children: [Child]
    @Query(sort: \DoseLog.timestamp, order: .reverse) private var allDoses: [DoseLog]
    @Query(sort: \TemperatureLog.timestamp, order: .reverse) private var allReadings: [TemperatureLog]
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context

    @State private var showPast = true
    @State private var showUpcoming = false
    @State private var selectedChildID: PersistentIdentifier? = nil   // nil = All
    @State private var exportFile: ExportFile?
    @State private var exportErrorMessage: String?
    @State private var selectedDose: DoseLog?
    @Namespace private var doseTransition

    // MARK: Computed
    private var visibleChildren: [Child] {
        viewModel.visibleChildrenForCurrentFamily(children)
    }

    private var visibleChildIDs: Set<PersistentIdentifier> {
        Set(visibleChildren.map(\.persistentModelID))
    }

    private var filteredDoses: [DoseLog] {
        if let id = selectedChildID {
            return allDoses.filter { $0.child?.persistentModelID == id }
        }

        // When participant devices have legacy local-only children, keep History focused
        // on shared family records to avoid misleading stale timelines.
        guard visibleChildren.count != children.count else { return allDoses }
        return allDoses.filter { dose in
            guard let childID = dose.child?.persistentModelID else { return false }
            return visibleChildIDs.contains(childID)
        }
    }

    private var filteredReadings: [TemperatureLog] {
        if let id = selectedChildID {
            return allReadings.filter { $0.child?.persistentModelID == id }
        }
        guard visibleChildren.count != children.count else { return allReadings }
        return allReadings.filter { reading in
            guard let childID = reading.child?.persistentModelID else { return false }
            return visibleChildIDs.contains(childID)
        }
    }

    /// Doses and temperature readings in one newest-first timeline.
    private var pastEntries: [PastEntry] {
        (filteredDoses.map(PastEntry.dose) + filteredReadings.map(PastEntry.reading))
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var filteredChildren: [Child] {
        guard let id = selectedChildID else { return Array(visibleChildren) }
        return visibleChildren.filter { $0.persistentModelID == id }
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
                            ) { withAnimation(.snappy) { selectedChildID = nil } }

                            ForEach(visibleChildren) { child in
                                FilterChip(
                                    label: child.name,
                                    isSelected: selectedChildID == child.persistentModelID,
                                    color: Color(hex: child.colorHex)
                                ) { withAnimation(.snappy) { selectedChildID = child.persistentModelID } }
                            }
                        }
                    }
                }
                .padding(10)
                .kidDoseGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal)

                contentArea
            }
            .padding(.top, 8)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            exportDoctorSummary()
                        } label: {
                            Label("Doctor Summary (PDF)", systemImage: "doc.richtext")
                        }
                        Button {
                            exportFullHistory()
                        } label: {
                            Label("All Doses (CSV)", systemImage: "tablecells")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(allDoses.isEmpty && allReadings.isEmpty)
                }
            }
            .navigationDestination(item: $selectedDose) { dose in
                DoseDetailView(dose: dose, onDelete: deleteFromDetail)
                    .kidDoseZoomDestination(id: dose.persistentModelID, in: doseTransition)
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

        if pastEntries.isEmpty {
            Spacer()
            Text("Nothing recorded yet")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List {
                ForEach(pastEntries) { entry in
                    pastRow(entry)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onDelete(perform: deleteEntries)
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
                if pastEntries.isEmpty {
                    Text("Nothing recorded yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pastEntries) { entry in
                        pastRow(entry)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deleteEntries)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private func pastRow(_ entry: PastEntry) -> some View {
        switch entry {
        case .dose(let dose):
            doseRow(dose)
        case .reading(let reading):
            ReadingRowView(reading: reading)
        }
    }

    private func doseRow(_ dose: DoseLog) -> some View {
        Button {
            selectedDose = dose
        } label: {
            DoseRowView(dose: dose)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .kidDoseZoomSource(id: dose.persistentModelID, in: doseTransition)
        .accessibilityHint("Shows the exact time and details for this dose")
    }

    // MARK: Toggle helpers

    private func togglePast() {
        if showPast && !showUpcoming { return }
        withAnimation(.snappy) { showPast.toggle() }
    }

    private func toggleUpcoming() {
        if showUpcoming && !showPast { return }
        withAnimation(.snappy) { showUpcoming.toggle() }
    }

    // MARK: Delete

    private func deleteEntries(at offsets: IndexSet) {
        let current = pastEntries
        let targets = offsets.compactMap { current.indices.contains($0) ? current[$0] : nil }
        for entry in targets {
            switch entry {
            case .dose(let dose):
                viewModel.deleteDose(dose, context: context)
            case .reading(let reading):
                viewModel.deleteReading(reading, context: context)
            }
        }
    }

    /// Pops the detail screen first, then deletes, so the detail view never renders a deleted model.
    private func deleteFromDetail(_ dose: DoseLog) {
        selectedDose = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            viewModel.deleteDose(dose, context: context)
        }
    }

    /// PDF of the last 7 days for the selected child (or every visible child).
    private func exportDoctorSummary() {
        let reportChildren = filteredChildren.filter { !$0.doses.isEmpty || !$0.temperatureReadings.isEmpty }
        guard !reportChildren.isEmpty else {
            exportErrorMessage = "Nothing to include yet. Log a dose or temperature first."
            return
        }
        do {
            let url = try DoctorReport.makePDF(
                children: reportChildren,
                since: Date.now.addingTimeInterval(-7 * 24 * 3600)
            )
            exportFile = ExportFile(url: url)
        } catch {
            exportErrorMessage = "Could not create the PDF: \(error.localizedDescription)"
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
                "amount"
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
            // Prefer the amount saved with the dose; older doses fall back to the current note.
            let note = dose.amount ?? dose.medicationEnum.flatMap { med in
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
                Image(systemName: isOn ? "checkmark.circle.fill" : systemImage)
                    .imageScale(.small)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, KidDoseLayout.compactHorizontalPadding)
            .padding(.vertical, KidDoseLayout.compactVerticalPadding)
            .foregroundStyle(isOn ? .primary : .secondary)
            .background(
                isOn ? color.opacity(0.16) : Color(.tertiarySystemBackground),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isOn ? color : .primary.opacity(0.08), lineWidth: 1.3)
            )
        }
        .buttonStyle(.plain)
    }
}

private enum PastEntry: Identifiable {
    case dose(DoseLog)
    case reading(TemperatureLog)

    var id: PersistentIdentifier {
        switch self {
        case .dose(let dose): return dose.persistentModelID
        case .reading(let reading): return reading.persistentModelID
        }
    }

    var timestamp: Date {
        switch self {
        case .dose(let dose): return dose.timestamp
        case .reading(let reading): return reading.timestamp
        }
    }
}

private struct ReadingRowView: View {
    let reading: TemperatureLog

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "thermometer.medium")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(reading.isFever ? .red : .primary)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(reading.child?.name ?? "Unknown")
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    if let celsius = reading.celsius {
                        Text(TemperatureFormat.display(celsius))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(reading.isFever ? .red : .primary)
                    } else {
                        Text("Symptoms")
                            .font(.subheadline)
                    }
                }
                .lineLimit(1)
                Text(reading.symptoms ?? "Recorded by \(reading.recordedBy)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(reading.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .kidDoseSubtleSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.medication.color.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: item.medication.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.child.name)
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(item.medication.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                Text(formattedAbsoluteTime(item.nextDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let remaining = item.nextDate.timeIntervalSince(context.date)
                if remaining > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(roughCountdown(remaining))
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundStyle(.primary)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(item.medication.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                    }
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                        }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .kidDoseSubtleSurface(cornerRadius: 16)
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
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.small)
                }
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
                .padding(.horizontal, KidDoseLayout.compactHorizontalPadding)
                .padding(.vertical, KidDoseLayout.compactVerticalPadding)
                .background(isSelected ? color.opacity(0.18) : Color(.tertiarySystemBackground), in: Capsule())
                .foregroundStyle(isSelected ? .primary : .secondary)
                .overlay(Capsule().strokeBorder(isSelected ? color : .primary.opacity(0.08), lineWidth: 1.5))
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
                        .foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(med.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(stats[med.displayName] ?? 0) doses")
                            .font(.subheadline.bold())
                            .contentTransition(.numericText())
                            .animation(.snappy, value: stats[med.displayName] ?? 0)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .kidDoseSubtleSurface(cornerRadius: 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .kidDoseCardSurface(cornerRadius: 20)
    }
}

// MARK: - Dose Row (Past)

private struct DoseRowView: View {
    let dose: DoseLog

    var medicationColor: Color { dose.medicationEnum?.color ?? .gray }
    var medicationIcon: String { dose.medicationEnum?.iconName ?? "pill" }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(medicationColor.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: medicationIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(dose.child?.name ?? "Unknown")
                        .font(.subheadline.bold())
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(dose.medication.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text(dose.givenBy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let amount = dose.amount {
                        Text("· \(amount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

            VStack(alignment: .trailing, spacing: 2) {
                Text(exactTimeLabel(dose.timestamp))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(relativeTimestamp(for: dose.timestamp, now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.trailing)
            .fixedSize()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .kidDoseSubtleSurface(cornerRadius: 16)
    }

    /// "14:32" today, "Yesterday 14:32", otherwise "Sat 4 Oct 14:32".
    private func exactTimeLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \(time)"
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
