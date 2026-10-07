import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget

struct KidDoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KidDoseLiveActivityAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    let primary = context.state.primaryItem
                    HStack(spacing: 6) {
                        Image(systemName: primary.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(primary.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(primary.medicationName)
                                .font(.caption.weight(.semibold))
                            Text(primary.childName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    let primary = context.state.primaryItem
                    let phase = primary.phase(at: .now)
                    CountdownText(item: primary, phase: phase, now: .now)
                        .font(islandTimerFont(large: context.state.preferLargeText ?? false))
                        .foregroundStyle(phase.tint(for: primary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 92, alignment: .trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let secondary = context.state.secondaryItem {
                        SecondaryDoseRow(item: secondary, now: .now, showsNote: false)
                    } else {
                        let primary = context.state.primaryItem
                        HStack {
                            Text(primary.phase(at: .now) == .upcoming ? "Ready" : "Ready since")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            Text(timestampLabel(for: primary.nextDose))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                let primary = context.state.primaryItem
                Image(systemName: primary.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primary.color)
            } compactTrailing: {
                let primary = context.state.primaryItem
                let phase = primary.phase(at: .now)
                CountdownText(item: primary, phase: phase, now: .now)
                    .font((context.state.preferLargeText ?? false) ? .caption.monospacedDigit() : .caption2.monospacedDigit())
                    .foregroundStyle(phase.tint(for: primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 60, alignment: .trailing)
            } minimal: {
                let primary = context.state.primaryItem
                let phase = primary.phase(at: .now)
                Image(systemName: phase == .upcoming ? primary.symbol : "checkmark.circle.fill")
                    .foregroundStyle(phase.tint(for: primary))
            }
            .keylineTint(context.state.primaryItem.color)
        }
    }
}

// MARK: - Lock Screen Banner

private struct LockScreenLiveActivityView: View {
    let state: KidDoseLiveActivityAttributes.ContentState

    var body: some View {
        // The view is rendered when the app pushes an update and again when the
        // activity's `staleDate` passes (the manager sets that to the next due time),
        // so evaluating "now" here is enough to flip waiting → ready on time.
        let now = Date.now
        let primary = state.primaryItem
        let phase = primary.phase(at: now)
        let tint = phase.tint(for: primary)
        let isCompact = (state.preferredLayoutStyle ?? "detailed") == "compact"
        let timerFont = countdownFont(large: state.preferLargeText ?? false)

        VStack(alignment: .leading, spacing: 8) {
            // Header: medication + child, status badge on the right.
            HStack(spacing: 8) {
                Circle()
                    .fill(primary.color.opacity(0.16))
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: primary.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(primary.color)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(primary.medicationName) · \(primary.childName)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !isCompact, let detail = primary.detailLine {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                StatusBadge(phase: phase, tint: tint)
            }

            // Countdown row.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let prefix = phase.prefix {
                    Text(prefix)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                CountdownText(item: primary, phase: phase, now: now, readyLabel: "Ready now")
                    .font(timerFont)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text(phase == .upcoming ? "at \(timestampLabel(for: primary.nextDose))" : "since \(timestampLabel(for: primary.nextDose))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Live progress through the dosing interval.
            if !isCompact, let lastDose = primary.lastDose, lastDose < primary.nextDose {
                ProgressView(
                    timerInterval: lastDose...primary.nextDose,
                    countsDown: false,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .progressViewStyle(.linear)
                .tint(tint)
            }

            if let secondary = state.secondaryItem {
                SecondaryDoseRow(item: secondary, now: now, showsNote: !isCompact)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Secondary Row

private struct SecondaryDoseRow: View {
    let item: DoseItem
    let now: Date
    let showsNote: Bool

    var body: some View {
        let phase = item.phase(at: now)
        let tint = phase.tint(for: item)
        HStack(spacing: 6) {
            Image(systemName: item.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.color)
            Text("\(item.medicationName) · \(item.childName)")
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if showsNote, let note = item.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if phase == .overdue {
                Text("Overdue")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
            CountdownText(item: item, phase: phase, now: now)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Building Blocks

/// The live part of every surface. Counts down while waiting (and stops at 0:00 instead
/// of counting up), shows "Now" when ready, and counts up while overdue.
private struct CountdownText: View {
    let item: DoseItem
    let phase: DosePhase
    let now: Date
    var readyLabel: String = "Now"

    var body: some View {
        switch phase {
        case .upcoming:
            Text(timerInterval: min(now, item.nextDose)...item.nextDose, countsDown: true)
        case .ready:
            Text(readyLabel)
        case .overdue:
            Text(item.nextDose, style: .timer)
        }
    }
}

private struct StatusBadge: View {
    let phase: DosePhase
    let tint: Color

    var body: some View {
        Text(phase.badgeTitle)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - Model Helpers

private enum DosePhase: Equatable {
    case upcoming
    case ready
    case overdue

    var prefix: String? {
        switch self {
        case .upcoming: return "Next dose in"
        case .ready:    return nil
        case .overdue:  return "Overdue by"
        }
    }

    var badgeTitle: String {
        switch self {
        case .upcoming: return "Waiting"
        case .ready:    return "Ready"
        case .overdue:  return "Overdue"
        }
    }

    func tint(for item: DoseItem) -> Color {
        switch self {
        case .upcoming: return item.color
        case .ready:    return .green
        case .overdue:  return .red
        }
    }
}

private struct DoseItem {
    let childName: String
    let medicationName: String
    let symbol: String
    let nextDose: Date
    let lastDose: Date?
    let intervalHours: Double?
    let note: String?

    var color: Color {
        Medication(rawValue: medicationName.lowercased())?.color ?? .accentColor
    }

    /// "Every 8h · 6 ml"
    var detailLine: String? {
        var parts: [String] = []
        if let intervalHours, intervalHours > 0 {
            parts.append("Every \(Int(intervalHours.rounded()))h")
        }
        if let note {
            parts.append(note)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Mirrors the Home screen: waiting until the window opens, "ready" for the
    /// first minute, then overdue.
    func phase(at now: Date) -> DosePhase {
        let remaining = nextDose.timeIntervalSince(now)
        if remaining > 0.5 { return .upcoming }
        if remaining > -60 { return .ready }
        return .overdue
    }
}

private extension KidDoseLiveActivityAttributes.ContentState {
    var primaryItem: DoseItem {
        DoseItem(
            childName: primaryChildName,
            medicationName: primaryMedicationName,
            symbol: primaryMedicationSymbol,
            nextDose: primaryNextDose,
            lastDose: primaryLastDose,
            intervalHours: primaryIntervalHours,
            note: sanitizedNote(primaryDoseNote)
        )
    }

    var secondaryItem: DoseItem? {
        guard
            let secondaryChildName,
            let secondaryMedicationName,
            let secondaryNextDose
        else { return nil }
        return DoseItem(
            childName: secondaryChildName,
            medicationName: secondaryMedicationName,
            symbol: secondaryMedicationSymbol ?? "pills.fill",
            nextDose: secondaryNextDose,
            lastDose: secondaryLastDose,
            intervalHours: secondaryIntervalHours,
            note: sanitizedNote(secondaryDoseNote)
        )
    }
}

private func sanitizedNote(_ note: String?) -> String? {
    guard let note else { return nil }
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed
}

private func countdownFont(large: Bool) -> Font {
    large ? .title.monospacedDigit().weight(.semibold) : .title2.monospacedDigit().weight(.semibold)
}

private func islandTimerFont(large: Bool) -> Font {
    large ? .title3.monospacedDigit().weight(.semibold) : .headline.monospacedDigit()
}

private func timestampLabel(for date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return date.formatted(.dateTime.hour().minute())
    }
    if calendar.isDateInTomorrow(date) {
        return "tomorrow \(date.formatted(.dateTime.hour().minute()))"
    }
    if calendar.isDateInYesterday(date) {
        return "yesterday \(date.formatted(.dateTime.hour().minute()))"
    }
    return date.formatted(.dateTime.month().day().hour().minute())
}
