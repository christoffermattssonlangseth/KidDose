import ActivityKit
import WidgetKit
import SwiftUI

struct KidDoseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KidDoseLiveActivityAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.primaryMedicationSymbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(medicationColor(for: context.state.primaryMedicationName))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.primaryMedicationName)
                                .font(.caption.weight(.semibold))
                            Text(context.state.primaryChildName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    let primaryTiming = timingState(for: context.state.primaryNextDose)
                    let timerColor = countdownColor(
                        for: context.state.primaryMedicationName,
                        timing: primaryTiming
                    )
                    Group {
                        if primaryTiming == .ready {
                            Text("now")
                        } else {
                            Text(context.state.primaryNextDose, style: .timer)
                        }
                    }
                    .font(islandTimerFont(large: context.state.preferLargeText ?? false))
                    .foregroundStyle(timerColor)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if
                        let secondaryMedicationName = context.state.secondaryMedicationName,
                        let secondaryChildName = context.state.secondaryChildName,
                        let secondaryNextDose = context.state.secondaryNextDose
                    {
                        HStack(spacing: 8) {
                            Text("\(secondaryMedicationName) · \(secondaryChildName)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            let secondaryTiming = timingState(for: secondaryNextDose)
                            let secondaryColor = countdownColor(
                                for: secondaryMedicationName,
                                timing: secondaryTiming
                            )
                            if secondaryTiming == .ready {
                                Text("now")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(secondaryColor)
                            } else {
                                Text(secondaryNextDose, style: .timer)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(secondaryColor)
                            }
                        }
                    } else {
                        HStack {
                            Text("KidDose")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 6)
                            Text(context.state.primaryNextDose, format: .dateTime.hour().minute())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.primaryMedicationSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(medicationColor(for: context.state.primaryMedicationName))
            } compactTrailing: {
                let primaryTiming = timingState(for: context.state.primaryNextDose)
                let timerColor = countdownColor(
                    for: context.state.primaryMedicationName,
                    timing: primaryTiming
                )
                Group {
                    if primaryTiming == .ready {
                        Text("now")
                    } else {
                        Text(context.state.primaryNextDose, style: .timer)
                    }
                }
                .font((context.state.preferLargeText ?? false) ? .caption.monospacedDigit() : .caption2.monospacedDigit())
                .foregroundStyle(timerColor)
            } minimal: {
                Image(systemName: context.state.primaryMedicationSymbol)
                    .foregroundStyle(medicationColor(for: context.state.primaryMedicationName))
            }
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let state: KidDoseLiveActivityAttributes.ContentState

    var body: some View {
        let primaryColor = medicationColor(for: state.primaryMedicationName)
        let primaryTiming = timingState(for: state.primaryNextDose)
        let primaryTimerColor = countdownColor(for: state.primaryMedicationName, timing: primaryTiming)
        let isCompact = (state.preferredLayoutStyle ?? "detailed") == "compact"
        let timerFont = countdownFont(large: state.preferLargeText ?? false)
        let primaryStatus = statusText(
            lastDose: state.primaryLastDose,
            intervalHours: state.primaryIntervalHours,
            nextDose: state.primaryNextDose,
            timing: primaryTiming
        )
        let primaryProgress = progressValue(
            lastDose: state.primaryLastDose,
            intervalHours: state.primaryIntervalHours,
            nextDose: state.primaryNextDose
        )

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: state.primaryMedicationSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(primaryColor)
                Text("\(state.primaryMedicationName) · \(state.primaryChildName)")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(state.primaryNextDose, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(prefixText(for: primaryTiming))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if primaryTiming == .ready {
                    Text("now")
                        .font(timerFont)
                        .foregroundStyle(primaryTimerColor)
                } else {
                    Text(state.primaryNextDose, style: .timer)
                        .font(timerFont)
                        .foregroundStyle(primaryTimerColor)
                }
                Spacer(minLength: 8)
                Text(primaryStatus)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(primaryTimerColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(primaryTimerColor)
            }

            if !isCompact {
                if let primaryProgress {
                    FullWidthProgressBar(value: primaryProgress, tint: primaryTimerColor)
                }

                HStack(spacing: 6) {
                    if let intervalHours = state.primaryIntervalHours {
                        InfoChip(text: "Every \(Int(intervalHours.rounded()))h")
                    }

                    if let note = sanitizedNote(state.primaryDoseNote) {
                        InfoChip(text: note)
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if
                let secondaryMedicationName = state.secondaryMedicationName,
                let secondaryChildName = state.secondaryChildName,
                let secondaryNextDose = state.secondaryNextDose
            {
                let secondaryTiming = timingState(for: secondaryNextDose)
                let secondaryColor = countdownColor(for: secondaryMedicationName, timing: secondaryTiming)
                HStack(spacing: 6) {
                    Text("\(secondaryMedicationName) · \(secondaryChildName)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    if !isCompact, let secondaryNote = sanitizedNote(state.secondaryDoseNote) {
                        InfoChip(text: secondaryNote)
                    }
                    Spacer(minLength: 8)
                    Text(timestampLabel(for: secondaryNextDose))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if secondaryTiming == .overdue {
                        Text("Overdue by")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    if secondaryTiming == .ready {
                        Text("now")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(secondaryColor)
                    } else {
                        Text(secondaryNextDose, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(secondaryColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack {
                    Text("No secondary medication countdown")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FullWidthProgressBar: View {
    let value: Double
    let tint: Color

    var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 0)
            let fillWidth = width * clampedValue

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.tertiarySystemFill))
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: fillWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 4)
    }
}

private struct InfoChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemBackground), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private func medicationColor(for medicationName: String) -> Color {
    switch medicationName.lowercased() {
    case "ibuprofen":
        return .orange
    case "paracetamol":
        return Color(red: 0.10, green: 0.28, blue: 0.72)
    default:
        return .accentColor
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

private enum DoseTimingState {
    case upcoming
    case ready
    case overdue
}

private func timingState(for nextDose: Date) -> DoseTimingState {
    let remaining = nextDose.timeIntervalSinceNow
    if remaining > 0.5 { return .upcoming }
    if remaining > -60 { return .ready }
    return .overdue
}

private func countdownColor(for medicationName: String, timing: DoseTimingState) -> Color {
    switch timing {
    case .upcoming:
        return medicationColor(for: medicationName)
    case .ready:
        return .green
    case .overdue:
        return .red
    }
}

private func prefixText(for timing: DoseTimingState) -> String {
    switch timing {
    case .upcoming:
        return "in"
    case .ready:
        return "ready"
    case .overdue:
        return "Overdue by"
    }
}

private func statusText(
    lastDose: Date?,
    intervalHours: Double?,
    nextDose: Date,
    timing: DoseTimingState
) -> String {
    if timing == .overdue {
        return "Overdue"
    }
    if timing == .ready {
        return "Ready"
    }

    guard
        let lastDose,
        let intervalHours
    else {
        return Date.now >= nextDose ? "Ready" : "Scheduled"
    }

    let readyAt = lastDose.addingTimeInterval(intervalHours * 3600)
    return Date.now >= readyAt ? "Ready" : "Waiting"
}

private func progressValue(lastDose: Date?, intervalHours: Double?, nextDose: Date) -> Double? {
    guard
        let lastDose,
        let intervalHours,
        intervalHours > 0
    else { return nil }

    let readyAt = lastDose.addingTimeInterval(intervalHours * 3600)
    let total = readyAt.timeIntervalSince(lastDose)
    guard total > 0 else { return nil }

    let elapsed = Date.now.timeIntervalSince(lastDose)
    return min(max(elapsed / total, 0), 1)
}

private func timestampLabel(for date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return date.formatted(.dateTime.hour().minute())
    }
    if calendar.isDateInTomorrow(date) {
        return "Tomorrow \(date.formatted(.dateTime.hour().minute()))"
    }
    return date.formatted(.dateTime.month().day().hour().minute())
}
