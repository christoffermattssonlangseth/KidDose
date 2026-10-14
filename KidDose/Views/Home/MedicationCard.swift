import SwiftUI

/// A compact medication card with collapsible advanced options.
struct MedicationCard: View {
    let medication: Medication
    let child: Child
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context

    @State private var selectedInterval: Double
    @State private var feedbackTrigger: Bool = false
    @State private var showDoseConfirmation: Bool = false
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
    var dailyLimit: DailyLimitStatus? { viewModel.dailyLimitStatus(for: medication, child: child) }
    var limitReached: Bool { dailyLimit?.isReached ?? false }

    var cardAccentColor: Color {
        if isOverdue { return .red }
        if canGive   { return .green }
        return medication.color
    }
    var cardShadowColor: Color {
        if isOverdue { return .red.opacity(0.22) }
        if canGive   { return .green.opacity(0.22) }
        return .black.opacity(0.06)
    }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(medication.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: medication.iconName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(medication.color)
                            .symbolEffect(.bounce, value: feedbackTrigger)
                    }
                Text(medication.displayName)
                    .font(.headline)
                Spacer()
                Group {
                    if isSessionEnded {
                        StatusPill(title: "Skipped", systemImage: "forward.circle.fill", tint: .orange)
                    } else if isOverdue {
                        StatusPill(title: "Overdue", systemImage: "exclamationmark.triangle.fill", tint: .red, pulses: true)
                    } else if canGive {
                        StatusPill(title: "Ready", systemImage: "checkmark.circle.fill", tint: .green)
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
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

            if let dailyLimit {
                DailyLimitRow(status: dailyLimit)
            }

            Button {
                showDoseNoteSheet = true
            } label: {
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
                } else {
                    Label("Add note", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
            .buttonStyle(.plain)

            if let sessionEndedAt {
                HStack(spacing: 6) {
                    Image(systemName: "forward.circle")
                        .foregroundStyle(.orange)
                    Text("Dose skipped \(relativeTimestamp(for: sessionEndedAt, now: .now))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let nextAllowedDate {
                CountdownView(
                    targetDate: nextAllowedDate,
                    startDate: lastDose?.timestamp,
                    medication: medication
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .kidDoseSubtleSurface(cornerRadius: 16)
            }

            Button {
                showDoseConfirmation = true
            } label: {
                Label {
                    Text("Give Dose")
                } icon: {
                    Image(systemName: "plus.circle.fill")
                        .symbolEffect(.bounce, value: feedbackTrigger)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .font(.subheadline.weight(.semibold))
            }
            .kidDoseProminentButton(tint: isOverdue ? .red : (canGive ? medication.color : .gray))
            .controlSize(.regular)
            .disabled(!canGive)
            .sensoryFeedback(.success, trigger: feedbackTrigger)
            .confirmationDialog(
                limitReached
                    ? "Daily limit reached for \(child.name)"
                    : "Give \(medication.displayName) to \(child.name)?",
                isPresented: $showDoseConfirmation,
                titleVisibility: .visible
            ) {
                Button(limitReached ? "Give Anyway" : "Confirm Dose", role: limitReached ? .destructive : nil) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        feedbackTrigger.toggle()
                    }
                    viewModel.logDose(
                        medication: medication,
                        intervalHours: selectedInterval,
                        for: child,
                        context: context
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let dailyLimit, dailyLimit.isReached {
                    Text(limitWarningText(dailyLimit))
                } else if let note = visibleDoseNote {
                    Text(note)
                }
            }

            DisclosureGroup(isExpanded: $showAdvancedOptions) {
                VStack(alignment: .leading, spacing: 8) {
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

                    Stepper(
                        value: Binding(
                            get: { child.maxDailyDoses(for: medication) ?? 0 },
                            set: { newValue in
                                viewModel.setMaxDailyDoses(
                                    newValue == 0 ? nil : newValue,
                                    for: medication,
                                    child: child,
                                    context: context
                                )
                            }
                        ),
                        in: 0...8
                    ) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Daily limit")
                                .font(.caption.weight(.semibold))
                            Text(limitSettingText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showRetroactiveSheet = true
                    } label: {
                        Label("Add Past Dose", systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

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
                                isSessionEnded ? "Resume Tracking" : "Skip Dose",
                                systemImage: isSessionEnded ? "play.circle" : "forward.circle"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
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
        .padding(14)
        .padding(.leading, 4)
        .kidDoseCardSurface(cornerRadius: 22)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(cardAccentColor)
                .frame(width: 4)
                .padding(.vertical, 16)
                .padding(.leading, 6)
        }
        .shadow(color: cardShadowColor, radius: 10, y: 4)
        .shadow(color: isOverdue ? .red.opacity(0.25) : .clear, radius: 14)
        .animation(.smooth, value: isOverdue)
        .animation(.smooth, value: canGive)
        .animation(.smooth, value: isSessionEnded)
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

    private var limitSettingText: String {
        guard let limit = child.maxDailyDoses(for: medication) else {
            return "Off. Set the max doses per 24 h from the leaflet or your doctor."
        }
        return limit == 1 ? "Warn after 1 dose in 24 h" : "Warn after \(limit) doses in 24 h"
    }

    private func limitWarningText(_ status: DailyLimitStatus) -> String {
        var text = "\(child.name) has had \(status.given) of \(status.limit) \(medication.displayName.lowercased()) doses in the last 24 hours."
        if let resetsAt = status.resetsAt {
            text += " The next dose is within the limit from \(resetsAt.formatted(date: .omitted, time: .shortened))."
        }
        return text + " Only continue if your doctor advised it."
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

// MARK: - Daily Limit

private struct DailyLimitRow: View {
    let status: DailyLimitStatus

    var body: some View {
        let tint: Color = status.isReached ? .red : (status.given + 1 >= status.limit ? .orange : .secondary)
        HStack(spacing: 8) {
            // One pip per allowed dose, filled for each dose given in the last 24 h.
            HStack(spacing: 3) {
                ForEach(0..<max(status.limit, 1), id: \.self) { index in
                    Capsule()
                        .fill(index < status.given ? tint : Color.primary.opacity(0.12))
                        .frame(width: 10, height: 5)
                }
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(status.isReached ? .red : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        if status.isReached {
            if let resetsAt = status.resetsAt {
                return "Daily limit reached · OK again at \(resetsAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Daily limit reached"
        }
        return "\(status.given) of \(status.limit) in the last 24 h"
    }
}

// MARK: - Live Countdown

struct CountdownView: View {
    let targetDate: Date
    var startDate: Date? = nil
    let medication: Medication

    // Scale with the user's text size setting.
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var ringSize: CGFloat = 64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = targetDate.timeIntervalSince(context.date)
            let progress = KidDoseTime.progress(start: startDate, end: targetDate, now: context.date)

            HStack(spacing: 16) {
                DoseProgressRing(
                    progress: remaining > 0 ? progress : 1,
                    tint: ringTint(remaining),
                    lineWidth: 7
                ) {
                    Image(systemName: ringSymbol(remaining))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ringTint(remaining))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, options: .repeating, isActive: remaining <= -60)
                }
                .frame(width: ringSize, height: ringSize)

                VStack(alignment: .leading, spacing: 2) {
                    if remaining > 0 {
                        Text(KidDoseTime.timer(remaining))
                            .font(.system(size: timerSize, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(medication.color)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(remaining))
                        Text("until next dose · ready at \(formattedTime(targetDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if remaining > -60 {
                        Text("Ready now")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundStyle(.green)
                        Text("Since \(formattedTime(targetDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Overdue \(formattedOverdue(-remaining))")
                            .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(.red)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: Int(-remaining / 60))
                        Text("Was due at \(formattedTime(targetDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func ringTint(_ remaining: TimeInterval) -> Color {
        if remaining > 0 { return medication.color }
        return remaining > -60 ? .green : .red
    }

    private func ringSymbol(_ remaining: TimeInterval) -> String {
        if remaining > 0 { return "hourglass" }
        return remaining > -60 ? "checkmark" : "exclamationmark"
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
