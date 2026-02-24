import SwiftUI

/// A large card showing one medication's status for the selected child, with a live countdown.
struct MedicationCard: View {
    let medication: Medication
    let child: Child
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context

    @State private var selectedInterval: Double
    @State private var feedbackTrigger: Bool = false
    @State private var showRetroactiveSheet: Bool = false
    @State private var showDoseNoteSheet: Bool = false

    init(medication: Medication, child: Child) {
        self.medication = medication
        self.child = child
        // Default to the latest logged interval for this child+medication if available.
        let initialInterval: Double
        if let lastDose = child.lastDose(for: medication), lastDose.usedIntervalHours > 0 {
            initialInterval = lastDose.usedIntervalHours
        } else {
            initialInterval = medication.intervalHours
        }
        _selectedInterval = State(initialValue: initialInterval)
    }

    var canGive: Bool { viewModel.canGiveDose(for: medication, child: child) }
    var nextDate: Date? { viewModel.nextDoseDate(for: medication, child: child) }
    var nextAllowedDate: Date? { viewModel.nextAllowedDate(for: medication, child: child) }
    var isOverdue: Bool { viewModel.overdueDuration(for: medication, child: child) != nil }
    var lastDose: DoseLog? { child.lastDose(for: medication) }
    var doseNote: String? { child.doseNote(for: medication) }
    var currentIntervalMode: Double {
        if let lastDose, lastDose.usedIntervalHours > 0 {
            return lastDose.usedIntervalHours
        }
        return selectedInterval
    }
    var switchIntervalTarget: Double {
        currentIntervalMode <= 6.5 ? 8.0 : 6.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Header ──────────────────────────────────────────────
            HStack {
                Image(systemName: medication.iconName)
                    .font(.title2)
                    .foregroundStyle(medication.color)
                Text(medication.displayName)
                    .font(.title3.bold())
                Spacer()
                if isOverdue {
                    Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                } else if canGive {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Divider()

            // ── Last dose ────────────────────────────────────────────
            if let last = lastDose {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last dose")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(last.relativeTimestamp)
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("by")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(last.givenBy)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                }
            } else {
                Text("No doses yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // ── Live countdown ───────────────────────────────────────
            if let next = nextDate {
                CountdownView(targetDate: next, medication: medication)
            }

            if let nextAllowedDate, isOverdue {
                OverdueView(nextAllowedDate: nextAllowedDate)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Dose note", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(doseNote == nil ? "Add" : "Edit") {
                        showDoseNoteSheet = true
                    }
                    .font(.caption.weight(.semibold))
                }

                Text(doseNote ?? "No note saved yet (e.g. 6 ml).")
                    .font(.subheadline)
                    .foregroundStyle(doseNote == nil ? .secondary : .primary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            // ── Interval picker (ibuprofen only) ─────────────────────
            if medication.availableIntervals.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Interval for next dose")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Interval", selection: $selectedInterval) {
                        ForEach(medication.availableIntervals, id: \.self) { hours in
                            Text("Every \(Int(hours))h").tag(hours)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if medication == .ibuprofen, lastDose != nil {
                    HStack {
                        Text("Current mode: every \(Int(currentIntervalMode))h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Switch to \(Int(switchIntervalTarget))h") {
                            selectedInterval = switchIntervalTarget
                            viewModel.setLatestDoseInterval(
                                for: medication,
                                intervalHours: switchIntervalTarget,
                                child: child,
                                context: context
                            )
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            // ── Give Dose button ─────────────────────────────────────
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    feedbackTrigger.toggle()
                }
                viewModel.logDose(
                    medication: medication,
                    intervalHours: selectedInterval,
                    for: child,
                    context: context
                )
            } label: {
                Label("Give Dose", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(isOverdue ? .red : (canGive ? medication.color : .gray))
            .disabled(!canGive)
            .sensoryFeedback(.impact, trigger: feedbackTrigger)

            Button {
                showRetroactiveSheet = true
            } label: {
                Label("Add Past Dose", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
        .sheet(isPresented: $showRetroactiveSheet) {
            RetroactiveDoseSheet(
                medication: medication,
                child: child,
                intervalHours: selectedInterval
            ) { pastTimestamp, setAsLatest in
                viewModel.logRetroactiveDose(
                    medication: medication,
                    intervalHours: selectedInterval,
                    timestamp: pastTimestamp,
                    setAsLatest: setAsLatest,
                    for: child,
                    context: context
                )
            }
        }
        .sheet(isPresented: $showDoseNoteSheet) {
            DoseNoteSheet(
                medication: medication,
                childName: child.name,
                initialNote: doseNote ?? ""
            ) { newNote in
                let trimmed = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
                child.setDoseNote(trimmed.isEmpty ? nil : trimmed, for: medication)
                try? context.save()
                Task {
                    await viewModel.syncChildToFamilyCloud(child, context: context)
                }
            }
        }
    }
}

private struct RetroactiveDoseSheet: View {
    let medication: Medication
    let child: Child
    let intervalHours: Double
    let onSave: (Date, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTimestamp = Calendar.current.date(
        byAdding: .hour,
        value: -1,
        to: .now
    ) ?? .now
    @State private var setAsLatest = true

    private var canSave: Bool {
        selectedTimestamp <= .now
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When was the dose given?") {
                    DatePicker(
                        "Dose time",
                        selection: $selectedTimestamp,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                }

                Section("Dose details") {
                    LabeledContent("Child", value: child.name)
                    LabeledContent("Medication", value: medication.displayName)
                    LabeledContent("Interval", value: "Every \(Int(intervalHours))h")
                }

                Section {
                    Toggle("Use as most recent dose", isOn: $setAsLatest)
                    Text("If on, any newer \(medication.displayName.lowercased()) entries for \(child.name) will be replaced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Past Dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(selectedTimestamp, setAsLatest)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct OverdueView: View {
    let nextAllowedDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let overdue = context.date.timeIntervalSince(nextAllowedDate)
            if overdue > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.red)
                    Text("Overdue by \(formatted(overdue))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}

private struct DoseNoteSheet: View {
    let medication: Medication
    let childName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(
        medication: Medication,
        childName: String,
        initialNote: String,
        onSave: @escaping (String) -> Void
    ) {
        self.medication = medication
        self.childName = childName
        self.onSave = onSave
        _note = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dose note for \(medication.displayName)") {
                    TextField("Example: 6 ml", text: $note, axis: .vertical)
                        .lineLimit(3...)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Saved per child and medication. Leave empty to clear.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Child", value: childName)
                }
            }
            .navigationTitle("Dose Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Live Countdown

struct CountdownView: View {
    let targetDate: Date
    let medication: Medication

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = targetDate.timeIntervalSince(context.date)
            if remaining > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(medication.color)
                    Text(formattedCountdown(remaining))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(medication.color)
                    Text("until next dose")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedCountdown(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        let s = Int(interval) % 60
        if h > 0 {
            return String(format: "%dh %02dm %02ds", h, m, s)
        }
        return String(format: "%dm %02ds", m, s)
    }
}
