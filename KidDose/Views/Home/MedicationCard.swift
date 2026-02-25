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
    var lastDose: DoseLog? { viewModel.latestDoseInCurrentCycle(for: medication, child: child) }
    var doseNote: String? { child.doseNote(for: medication) }
    var sessionEndedAt: Date? { viewModel.sessionEndedAt(for: medication, child: child) }
    var isSessionEnded: Bool { viewModel.isMedicationSessionEnded(for: medication, child: child) }
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
        VStack(alignment: .leading, spacing: 8) {

            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: medication.iconName)
                    .font(.title3)
                    .foregroundStyle(medication.color)
                Text(medication.displayName)
                    .font(.headline.weight(.semibold))
                Spacer()
                if isSessionEnded {
                    Label("Cycle Ended", systemImage: "pause.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if isOverdue {
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
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last dose")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(relativeTimestamp(for: last.timestamp, now: context.date))
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
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

            if let sessionEndedAt {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.orange)
                    Text("Cycle ended \(relativeTimestamp(for: sessionEndedAt, now: .now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // ── Live countdown ───────────────────────────────────────
            if let next = nextDate {
                CountdownView(targetDate: next, medication: medication)
            }

            if let nextAllowedDate, isOverdue {
                OverdueView(nextAllowedDate: nextAllowedDate)
            }

            VStack(alignment: .leading, spacing: 4) {
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
            .padding(8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            // ── Interval picker (ibuprofen only) ─────────────────────
            if medication.availableIntervals.count > 1 {
                VStack(alignment: .leading, spacing: 3) {
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
                    .padding(.vertical, 8)
                    .font(.subheadline.weight(.semibold))
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
                    .padding(.vertical, 6)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)

            if lastDose != nil {
                Button {
                    if isSessionEnded {
                        viewModel.restartMedicationSession(
                            for: medication,
                            child: child,
                            context: context
                        )
                    } else {
                        viewModel.endMedicationSession(
                            for: medication,
                            child: child,
                            context: context
                        )
                    }
                } label: {
                    Label(
                        isSessionEnded ? "Restart Cycle" : "End Cycle",
                        systemImage: isSessionEnded ? "play.circle" : "pause.circle"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(isSessionEnded ? medication.color : .orange)
            }

        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
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

    private func relativeTimestamp(for timestamp: Date, now: Date) -> String {
        // Cloud/device clock drift can place synced records a few seconds in the future.
        // Clamp to "just now" near zero so "time since last dose" stays intuitive.
        let delta = now.timeIntervalSince(timestamp)
        if abs(delta) < 30 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: now)
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
                HStack(spacing: 6) {
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
                VStack(alignment: .leading, spacing: 4) {
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
                    Text("Ready at \(formattedTime(targetDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 22)
                }
            }
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
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
