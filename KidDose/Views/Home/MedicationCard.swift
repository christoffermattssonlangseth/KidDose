import SwiftUI

/// A compact medication card with collapsible advanced options.
struct MedicationCard: View {
    let medication: Medication
    let child: Child
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context

    @State private var selectedInterval: Double
    @State private var feedbackTrigger: Bool = false
    @State private var showRetroactiveSheet: Bool = false
    @State private var showDoseNoteSheet: Bool = false
    @State private var showAdvancedOptions: Bool = false

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

    var nextAllowedDate: Date? { viewModel.nextAllowedDate(for: medication, child: child) }
    var canGive: Bool {
        guard let nextAllowedDate else { return true }
        return Date.now >= nextAllowedDate
    }
    var isOverdue: Bool {
        guard let nextAllowedDate else { return false }
        return Date.now >= nextAllowedDate
    }
    var lastDose: DoseLog? { viewModel.latestDoseInCurrentCycle(for: medication, child: child) }
    var doseNote: String? { child.doseNote(for: medication) }
    var visibleDoseNote: String? {
        guard
            let trimmedNote = doseNote?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmedNote.isEmpty
        else {
            return nil
        }
        return trimmedNote
    }
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
            HStack(spacing: 8) {
                Circle()
                    .fill(medication.color.opacity(0.14))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: medication.iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(medication.color)
                    }
                Text(medication.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isSessionEnded {
                    Label("Cycle Ended", systemImage: "pause.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if isOverdue {
                    Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else if canGive {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if let last = lastDose {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Text("Last \(relativeTimestamp(for: last.timestamp, now: timeline.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(last.givenBy)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No doses yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let visibleDoseNote {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(visibleDoseNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, KidDoseLayout.compactHorizontalPadding)
                .padding(.vertical, KidDoseLayout.compactVerticalPadding)
                .kidDoseSubtleSurface()
            }

            if let sessionEndedAt {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.orange)
                    Text("Cycle ended \(relativeTimestamp(for: sessionEndedAt, now: .now))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let nextAllowedDate {
                CountdownView(targetDate: nextAllowedDate, medication: medication)
                    .padding(.horizontal, KidDoseLayout.compactHorizontalPadding)
                    .padding(.vertical, KidDoseLayout.compactVerticalPadding)
                    .kidDoseSubtleSurface()
            }

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
                    .padding(.vertical, KidDoseLayout.compactVerticalPadding)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isOverdue ? .red : (canGive ? medication.color : .gray))
            .disabled(!canGive)
            .sensoryFeedback(.impact, trigger: feedbackTrigger)

            DisclosureGroup(isExpanded: $showAdvancedOptions) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(visibleDoseNote == nil ? "Dose note" : "Edit dose note", systemImage: "note.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(doseNote == nil ? "Add" : "Edit") {
                                showDoseNoteSheet = true
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(8)
                    .kidDoseSubtleSurface()

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

                    Button {
                        showRetroactiveSheet = true
                    } label: {
                        Label("Add Past Dose", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

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
                        .controlSize(.small)
                        .tint(isSessionEnded ? medication.color : .orange)
                    }
                }
                .padding(.top, 4)
            } label: {
                Label("More options", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .kidDoseCardSurface(cornerRadius: 13)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(medication.color.opacity(0.9))
                .frame(width: 3)
                .padding(.vertical, 10)
        }
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
                    Text(
                        "If on, any newer \(medication.displayName.lowercased()) entries for \(child.name) will be replaced."
                    )
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
            if remaining > 0.5 {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(medication.color)
                    Text(formattedCountdown(remaining))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(medication.color)
                    Text("to next dose")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedTime(targetDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if remaining > -60 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Dose ready now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.red)
                    Text("Overdue by \(formattedOverdue(-remaining))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.red)
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

    private func formattedOverdue(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}
