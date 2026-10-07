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
    /// Counts every dose, so Skip / New Cycle can't unlock Give while a dose is still active.
    var availability: DoseAvailability { viewModel.doseAvailability(for: medication, child: child) }
    var canGive: Bool { availability.isAllowed }
    var maxDailyDoses: Int? { child.maxDailyDoses(for: medication) }
    var isOverdue: Bool {
        guard let nextAllowedDate else { return false }
        return Date.now >= nextAllowedDate
    }
    var lastDose: DoseLog? { viewModel.latestDoseInCurrentCycle(for: medication, child: child) }

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
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            lastDoseLine
            noteButton
            sessionEndedLine
            countdownBlock
            dailyLimitLine
            giveDoseButton
            advancedDrawer
        }
        .padding(12)
        .kidDoseCardSurface(cornerRadius: 13)
        .overlay(alignment: .leading) { accentStripe }
        .shadow(color: cardShadowColor, radius: 6, y: 2)
        .shadow(color: isOverdue ? .red.opacity(0.25) : .clear, radius: 12)
        .sheet(isPresented: $showRetroactiveSheet) { retroactiveSheet }
        .sheet(isPresented: $showDoseNoteSheet) { doseNoteSheet }
    }

    // MARK: - Subviews

    @ViewBuilder private var headerRow: some View {
        HStack(spacing: 10) {
            DoseProgressIcon(
                medication: medication,
                lastDose: lastDose,
                nextAllowedDate: nextAllowedDate,
                isOverdue: isOverdue,
                isReady: canGive,
                isSessionEnded: isSessionEnded
            )
            Text(medication.displayName)
                .font(.subheadline.weight(.semibold))
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder private var statusBadge: some View {
        if isSessionEnded {
            StatusBadge(
                text: "Dose Skipped",
                systemImage: "forward.circle.fill",
                tone: .skipped,
                accessibilityDescription: "\(medication.displayName) skipped for \(child.name)"
            )
        } else if isOverdue {
            StatusBadge(
                text: "Overdue",
                systemImage: "exclamationmark.triangle.fill",
                tone: .overdue,
                bounceOn: isOverdue,
                accessibilityDescription: "\(medication.displayName) overdue for \(child.name)"
            )
        } else if canGive {
            StatusBadge(
                text: "Ready",
                systemImage: "checkmark.circle.fill",
                tone: .ready,
                bounceOn: canGive,
                accessibilityDescription: "\(medication.displayName) ready for \(child.name)"
            )
        }
    }

    @ViewBuilder private var lastDoseLine: some View {
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
    }

    @ViewBuilder private var noteButton: some View {
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
                Label("Add note or daily limit", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground), in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var sessionEndedLine: some View {
        if let sessionEndedAt {
            HStack(spacing: 6) {
                Image(systemName: "forward.circle")
                    .foregroundStyle(.orange)
                Text("Dose skipped \(relativeTimestamp(for: sessionEndedAt, now: .now))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var countdownBlock: some View {
        // After Skip / New Cycle there is no scheduled window, but an earlier dose may
        // still block the next one — count down to that instead.
        if let target = nextAllowedDate ?? availability.blockedUntil {
            CountdownView(targetDate: target, medication: medication)
                .padding(.horizontal, KidDoseLayout.compactHorizontalPadding)
                .padding(.vertical, KidDoseLayout.compactVerticalPadding)
                .kidDoseSubtleSurface()
        }
    }

    @ViewBuilder private var dailyLimitLine: some View {
        if let maxDailyDoses {
            let given = viewModel.dosesInLast24h(for: medication, child: child)
            let limitReached: Bool = {
                if case .dailyLimitReached = availability { return true }
                return false
            }()
            Label(
                limitReached
                    ? "Daily limit reached: \(given) of \(maxDailyDoses) in 24 h"
                    : "\(given) of \(maxDailyDoses) doses in the last 24 h",
                systemImage: limitReached ? "exclamationmark.octagon.fill" : "24.circle"
            )
            .font(.caption.weight(limitReached ? .semibold : .regular))
            .foregroundStyle(limitReached ? Color.red : Color.secondary)
        }
    }

    @ViewBuilder private var giveDoseButton: some View {
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
            .padding(.vertical, KidDoseLayout.compactVerticalPadding)
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(isOverdue ? .red : (canGive ? medication.color : .gray))
        .disabled(!canGive)
        .accessibilityLabel("Give \(medication.displayName) to \(child.name)")
        .accessibilityHint(canGive ? "Logs a dose now." : "Disabled until the next dose is safe.")
        .sensoryFeedback(.impact, trigger: feedbackTrigger)
        .confirmationDialog(
            "Give \(medication.displayName) to \(child.name)?",
            isPresented: $showDoseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Confirm Dose") {
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
            if let note = visibleDoseNote {
                Text(note)
            }
        }
    }

    @ViewBuilder private var advancedDrawer: some View {
        DisclosureGroup(isExpanded: $showAdvancedOptions) {
            VStack(alignment: .leading, spacing: 8) {
                if medication.availableIntervals.count > 1 {
                    intervalPicker
                    if medication == .ibuprofen, lastDose != nil {
                        intervalSwitchRow
                    }
                }
                addPastDoseButton
                if lastDose != nil { skipOrResumeButton }
            }
            .padding(.top, 4)
        } label: {
            Label("More options", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder private var intervalPicker: some View {
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
    }

    @ViewBuilder private var intervalSwitchRow: some View {
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

    @ViewBuilder private var addPastDoseButton: some View {
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
        .tint(medication.color)
    }

    @ViewBuilder private var skipOrResumeButton: some View {
        Button {
            if isSessionEnded {
                viewModel.restartMedicationSession(for: medication, child: child, context: context)
            } else {
                viewModel.endMedicationSession(for: medication, child: child, context: context)
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
        .controlSize(.small)
        .tint(isSessionEnded ? medication.color : .orange)
    }

    private var accentStripe: some View {
        Rectangle()
            .fill(cardAccentColor)
            .frame(width: 4)
            .clipShape(.rect(topLeadingRadius: 13, bottomLeadingRadius: 13))
    }

    private var retroactiveSheet: some View {
        RetroactiveDoseSheet(
            medication: medication,
            child: child,
            intervalHours: selectedInterval,
            newerDoseCount: { timestamp in
                viewModel.newerDosesInCurrentCycle(than: timestamp, medication: medication, child: child).count
            },
            conflicts: { timestamp, setAsLatest in
                viewModel.pastDoseConflicts(
                    medication: medication,
                    intervalHours: selectedInterval,
                    timestamp: timestamp,
                    replacingNewer: setAsLatest,
                    child: child
                )
            }
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

    private var doseNoteSheet: some View {
        DoseNoteSheet(
            medication: medication,
            childName: child.name,
            initialNote: doseNote ?? "",
            initialMaxDailyDoses: maxDailyDoses
        ) { newNote, newMaxDailyDoses in
            let trimmed = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.setDoseInstructions(
                note: trimmed.isEmpty ? nil : trimmed,
                maxDailyDoses: newMaxDailyDoses,
                for: medication,
                child: child,
                context: context
            )
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
    let newerDoseCount: (Date) -> Int
    let conflicts: (Date, Bool) -> [DoseConflict]
    let onSave: (Date, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTimestamp = Calendar.current.date(
        byAdding: .hour,
        value: -1,
        to: .now
    ) ?? .now
    // Off by default: replacing deletes newer doses (possibly a partner's) on every device.
    @State private var setAsLatest = false

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
                    Toggle("Replace newer doses", isOn: $setAsLatest)
                    let newerCount = newerDoseCount(selectedTimestamp)
                    if setAsLatest, newerCount > 0 {
                        Label(
                            "Deletes \(newerCount) newer \(medication.displayName.lowercased()) \(newerCount == 1 ? "dose" : "doses") for \(child.name) on every family device. Only use this to correct a dose logged at the wrong time.",
                            systemImage: "trash"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    } else {
                        Text(
                            "Off: the dose is added to the history and newer doses are kept. On: newer \(medication.displayName.lowercased()) entries in the current infection cycle are deleted."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                let ruleConflicts = conflicts(selectedTimestamp, setAsLatest)
                if !ruleConflicts.isEmpty {
                    Section("Check this dose") {
                        ForEach(Array(ruleConflicts.enumerated()), id: \.offset) { _, conflict in
                            Label(
                                conflict.explanation(medicationName: medication.displayName),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                        Text("It will still be recorded, because it was already given.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
    let onSave: (String, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var limitEnabled: Bool
    @State private var maxDailyDoses: Int

    init(
        medication: Medication,
        childName: String,
        initialNote: String,
        initialMaxDailyDoses: Int?,
        onSave: @escaping (String, Int?) -> Void
    ) {
        self.medication = medication
        self.childName = childName
        self.onSave = onSave
        _note = State(initialValue: initialNote)
        _limitEnabled = State(initialValue: initialMaxDailyDoses != nil)
        _maxDailyDoses = State(initialValue: initialMaxDailyDoses ?? 4)
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
                    Toggle("Limit doses per 24 h", isOn: $limitEnabled.animation())
                    if limitEnabled {
                        Stepper("Max \(maxDailyDoses) doses in 24 h", value: $maxDailyDoses, in: 1...8)
                    }
                } header: {
                    Text("Daily limit")
                } footer: {
                    Text("Use the maximum from your product's package leaflet or your doctor. KidDose blocks Give Dose once the limit is reached within any 24 hours.")
                }
                Section {
                    Text("Saved per child and medication and shared with your family. Leave the note empty to clear it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Child", value: childName)
                }
            }
            .navigationTitle("Dose Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(note, limitEnabled ? maxDailyDoses : nil)
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
                VStack(spacing: 4) {
                    Text(formattedCountdown(remaining))
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(medication.color)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.easeOut(duration: 0.25), value: Int(remaining))
                    HStack(spacing: 4) {
                        Text("until next dose")
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("Ready at \(formattedTime(targetDate))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(spokenCountdown(remaining)) until next dose. Ready at \(formattedTime(targetDate))."
                )
            } else if remaining > -60 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Dose ready now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Dose ready now")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.red)
                    Text("Overdue by \(formattedOverdue(-remaining))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: Int(-remaining))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Overdue by \(spokenCountdown(-remaining))")
            }
        }
    }

    private func spokenCountdown(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        switch (h, m) {
        case (0, 0): return "less than a minute"
        case (0, _): return "\(m) minute\(m == 1 ? "" : "s")"
        case (_, 0): return "\(h) hour\(h == 1 ? "" : "s")"
        default:     return "\(h) hour\(h == 1 ? "" : "s") \(m) minute\(m == 1 ? "" : "s")"
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

// MARK: - Dose Progress Icon

/// A medication icon wrapped in a ring that fills as the current dose interval
/// elapses. Gives an at-a-glance read of how close the next dose is.
private struct DoseProgressIcon: View {
    let medication: Medication
    let lastDose: DoseLog?
    let nextAllowedDate: Date?
    let isOverdue: Bool
    let isReady: Bool
    let isSessionEnded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let diameter: CGFloat = 40
    private let lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let progress = computeProgress(now: context.date)

            ZStack {
                Circle()
                    .fill(medication.color.opacity(0.14))

                Circle()
                    .stroke(medication.color.opacity(0.18), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress)

                Image(systemName: medication.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(medication.color)
                    .modifier(PulseIfOverdue(active: isOverdue && !reduceMotion))
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityHidden(true)
    }

    private var ringColor: Color {
        if isSessionEnded { return .orange }
        if isOverdue      { return .red }
        if isReady        { return .green }
        return medication.color
    }

    private func computeProgress(now: Date) -> Double {
        guard isReady == false, isOverdue == false else { return 1 }
        guard
            let lastDose,
            let nextAllowedDate
        else { return 0 }
        let total = nextAllowedDate.timeIntervalSince(lastDose.timestamp)
        guard total > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(lastDose.timestamp)
        return max(0, min(1, elapsed / total))
    }
}

private struct PulseIfOverdue: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.symbolEffect(.pulse, options: .repeating)
        } else {
            content
        }
    }
}
