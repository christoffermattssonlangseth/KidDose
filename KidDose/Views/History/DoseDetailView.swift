import SwiftUI
import SwiftData
import UIKit

/// Full details for a single logged dose, opened by tapping a row in History.
struct DoseDetailView: View {
    let dose: DoseLog
    /// Called when the user confirms deletion. The parent pops this screen first,
    /// then deletes, so the view never reads a deleted model.
    let onDelete: (DoseLog) -> Void

    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context
    @State private var showDeleteConfirmation = false
    @State private var didCopy = false
    @State private var showAmountEditor = false
    @ScaledMetric(relativeTo: .largeTitle) private var headerTimeSize: CGFloat = 40
    @State private var amountDraft = ""

    var body: some View {
        // A partner's sync can remove this dose while the screen is open.
        if dose.isDeleted || dose.modelContext == nil {
            ContentUnavailableView(
                "Dose removed",
                systemImage: "trash",
                description: Text("This dose is no longer in the history.")
            )
        } else {
            details
        }
    }

    // MARK: - Content

    private var details: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if let warning = earlyDoseWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Date", value: fullDateText(dose.timestamp))
                LabeledContent("Time", value: dose.timestamp.formatted(date: .omitted, time: .standard))
                LabeledContent("Given by", value: dose.givenBy)
                LabeledContent("Interval") {
                    Text(intervalText)
                }
                Button {
                    amountDraft = dose.amount ?? ""
                    showAmountEditor = true
                } label: {
                    LabeledContent("Amount") {
                        HStack(spacing: 4) {
                            Text(dose.amount ?? "Add")
                                .foregroundStyle(dose.amount == nil ? Color.accentColor : .secondary)
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .tint(.primary)
                if dose.amount == nil, let note = doseNote {
                    LabeledContent("Current dose note", value: note)
                }
            } header: {
                Text("Dose")
            } footer: {
                if dose.amount == nil, doseNote != nil {
                    Text("This dose was logged before amounts were saved per dose, so the child's current note is shown.")
                }
            }

            Section {
                previousDoseRow
                followUpRow
                if let other = otherMedicationBefore {
                    LabeledContent("Last \(other.medication.displayName) before") {
                        TimeGapValue(
                            gap: dose.timestamp.timeIntervalSince(other.dose.timestamp),
                            suffix: "before",
                            date: other.dose.timestamp
                        )
                    }
                }
                LabeledContent("\(medicationName) in 24 h") {
                    Text(dosesIn24h == 1 ? "1 dose" : "\(dosesIn24h) doses")
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("The 24 h count includes this dose and any \(medicationName.lowercased()) given in the 24 hours before it.")
            }

            Section("Course") {
                LabeledContent("Illness course", value: isEarlierCourse ? "Earlier course" : "Current course")
                if viewModel.familySyncEnabled {
                    LabeledContent(
                        "Family sharing",
                        value: dose.cloudRecordName != nil ? "Shared" : "This device only"
                    )
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = summaryText
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy Details", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Dose", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(medicationName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: summaryText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .alert("Amount given", isPresented: $showAmountEditor) {
            TextField("e.g. 6 ml", text: $amountDraft)
            Button("Save") {
                viewModel.setAmount(amountDraft, for: dose, context: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved with this dose only.")
        }
        .confirmationDialog(
            "Delete this \(medicationName.lowercased()) dose?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Dose", role: .destructive) {
                onDelete(dose)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Timers, notifications and the Lock Screen will update. This also removes it for your family if sharing is on.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(medicationColor.opacity(0.16))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: medication?.iconName ?? "pill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(medicationColor)
                }

            HStack(spacing: 6) {
                if let child = dose.child {
                    Circle()
                        .fill(Color(hex: child.colorHex))
                        .frame(width: 10, height: 10)
                }
                Text("\(medicationName) · \(dose.child?.name ?? "Unknown child")")
                    .font(.headline)
            }

            Text(dose.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: headerTimeSize, weight: .semibold, design: .rounded).monospacedDigit())

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text("\(fullDateText(dose.timestamp)) · \(agoText(from: dose.timestamp, now: context.date))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Timing rows

    @ViewBuilder
    private var previousDoseRow: some View {
        if let previous = previousSameMedication {
            LabeledContent("Since previous \(medicationName.lowercased())") {
                TimeGapValue(
                    gap: dose.timestamp.timeIntervalSince(previous.timestamp),
                    suffix: nil,
                    date: previous.timestamp
                )
            }
        } else {
            LabeledContent("Previous \(medicationName.lowercased())", value: "None earlier")
        }
    }

    @ViewBuilder
    private var followUpRow: some View {
        if let next = nextSameMedication {
            LabeledContent("Next \(medicationName.lowercased()) given") {
                TimeGapValue(
                    gap: next.timestamp.timeIntervalSince(dose.timestamp),
                    suffix: "later",
                    date: next.timestamp
                )
            }
        } else if let skippedAt = skippedAfterThisDose {
            LabeledContent("Dose skipped") {
                Text(shortDateTimeText(skippedAt))
            }
        } else if isEarlierCourse {
            LabeledContent("Next dose allowed", value: "Course ended")
        } else {
            LabeledContent("Next dose allowed") {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let remaining = nextAllowedDate.timeIntervalSince(context.date)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(shortDateTimeText(nextAllowedDate))
                        if remaining > 0 {
                            Text("in \(durationText(remaining))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Ready now")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Derived facts

    private var medication: Medication? { dose.medicationEnum }
    private var medicationName: String { medication?.displayName ?? dose.medication.capitalized }
    private var medicationColor: Color { medication?.color ?? .gray }

    private var intervalHours: Double {
        effectiveInterval(of: dose)
    }

    private var intervalText: String {
        let hours = formatHours(intervalHours)
        if let medication, intervalHours == medication.intervalHours {
            return "Every \(hours) h (default)"
        }
        return "Every \(hours) h"
    }

    private var nextAllowedDate: Date {
        dose.timestamp.addingTimeInterval(intervalHours * 3600)
    }

    private var doseNote: String? {
        guard let medication, let note = dose.child?.doseNote(for: medication) else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Other doses of the same medication for the same child, oldest first.
    private var sameMedicationDoses: [DoseLog] {
        guard let child = dose.child else { return [] }
        return child.doses
            .filter { $0.medication == dose.medication && $0.persistentModelID != dose.persistentModelID }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var previousSameMedication: DoseLog? {
        sameMedicationDoses.last { $0.timestamp <= dose.timestamp }
    }

    private var nextSameMedication: DoseLog? {
        sameMedicationDoses.first { $0.timestamp > dose.timestamp }
    }

    private var otherMedicationBefore: (medication: Medication, dose: DoseLog)? {
        guard let child = dose.child else { return nil }
        let candidate = child.doses
            .filter { $0.medication != dose.medication && $0.timestamp <= dose.timestamp }
            .max { $0.timestamp < $1.timestamp }
        guard let candidate, let other = candidate.medicationEnum else { return nil }
        return (other, candidate)
    }

    private var dosesIn24h: Int {
        let windowStart = dose.timestamp.addingTimeInterval(-24 * 3600)
        let earlier = sameMedicationDoses.filter { $0.timestamp > windowStart && $0.timestamp <= dose.timestamp }
        return earlier.count + 1
    }

    /// Set when this dose was given before the previous dose's interval had passed.
    private var earlyDoseWarning: String? {
        guard let previous = previousSameMedication else { return nil }
        let required = effectiveInterval(of: previous) * 3600
        let gap = dose.timestamp.timeIntervalSince(previous.timestamp)
        // Allow a minute of slack for doses logged right as the timer finished.
        guard gap < required - 60 else { return nil }
        let early = required - gap
        return "Given \(durationText(early)) before the \(formatHours(effectiveInterval(of: previous))) h interval had passed."
    }

    private var isEarlierCourse: Bool {
        guard let medication, let start = dose.child?.cycleStartAt(for: medication) else { return false }
        return dose.timestamp < start
    }

    /// The "Dose Skipped" time when the course was ended after this, the latest dose.
    private var skippedAfterThisDose: Date? {
        guard let medication, let endedAt = dose.child?.sessionEndedAt(for: medication) else { return nil }
        return endedAt >= dose.timestamp ? endedAt : nil
    }

    private var summaryText: String {
        var lines = [
            "\(medicationName) for \(dose.child?.name ?? "Unknown child")",
            "Given: \(fullDateText(dose.timestamp)) at \(dose.timestamp.formatted(date: .omitted, time: .standard))",
            "Given by: \(dose.givenBy)",
            "Interval: every \(formatHours(intervalHours)) h",
        ]
        if nextSameMedication == nil, skippedAfterThisDose == nil, !isEarlierCourse {
            lines.append("Next dose allowed: \(shortDateTimeText(nextAllowedDate))")
        }
        if let amount = dose.amount {
            lines.append("Amount: \(amount)")
        }
        if let warning = earlyDoseWarning {
            lines.append("Warning: \(warning)")
        }
        return lines.joined(separator: "\n")
    }

    private func effectiveInterval(of log: DoseLog) -> Double {
        if log.usedIntervalHours > 0 { return log.usedIntervalHours }
        return log.medicationEnum?.intervalHours ?? 0
    }
}

// MARK: - Gap value

/// "6h 5m" on top, "Sat 4 Oct 14:32" underneath.
private struct TimeGapValue: View {
    let gap: TimeInterval
    let suffix: String?
    let date: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(suffix.map { "\(durationText(gap)) \($0)" } ?? durationText(gap))
            Text(shortDateTimeText(date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Formatting

private func durationText(_ interval: TimeInterval) -> String {
    let seconds = abs(interval)
    if seconds < 60 { return "under 1 min" }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = seconds >= 24 * 3600 ? [.day, .hour] : [.hour, .minute]
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll
    return formatter.string(from: seconds) ?? ""
}

private func agoText(from date: Date, now: Date) -> String {
    let delta = now.timeIntervalSince(date)
    if abs(delta) < 60 { return "just now" }
    return delta > 0 ? "\(durationText(delta)) ago" : "in \(durationText(delta))"
}

private func fullDateText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
}

private func shortDateTimeText(_ date: Date) -> String {
    let calendar = Calendar.current
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(date) { return "Today \(time)" }
    if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
    if calendar.isDateInTomorrow(date) { return "Tomorrow \(time)" }
    return "\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) \(time)"
}

private func formatHours(_ hours: Double) -> String {
    hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
}
