import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct KidDoseWidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [WidgetChildSnapshot]
}

// MARK: - Timeline Provider

struct KidDoseWidgetProvider: TimelineProvider {
    private static let sampleSnapshots: [WidgetChildSnapshot] = [
        WidgetChildSnapshot(
            name: "Emma",
            colorHex: "#FF6B35",
            ibuprofenNextDate: Date.now.addingTimeInterval(5400),
            paracetamolNextDate: nil,
            ibuprofenHasDoses: true,
            paracetamolHasDoses: true
        )
    ]

    func placeholder(in context: Context) -> KidDoseWidgetEntry {
        KidDoseWidgetEntry(date: .now, snapshots: Self.sampleSnapshots)
    }

    func getSnapshot(in context: Context, completion: @escaping (KidDoseWidgetEntry) -> Void) {
        let snapshots = WidgetDataStore.read()
        if context.isPreview && snapshots.isEmpty {
            completion(KidDoseWidgetEntry(date: .now, snapshots: Self.sampleSnapshots))
        } else {
            completion(KidDoseWidgetEntry(date: .now, snapshots: snapshots))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KidDoseWidgetEntry>) -> Void) {
        let snapshots = WidgetDataStore.read()
        let now = Date.now

        // One entry now, then one at each upcoming dose window (and one a minute later, when
        // Home switches from "Ready" to "Overdue"). The widget flips state exactly on time
        // instead of waiting for iOS to grant a reload.
        let dueDates = snapshots
            .flatMap { [$0.ibuprofenNextDate, $0.paracetamolNextDate] }
            .compactMap { $0 }
            .filter { $0 > now }
            .sorted()
            .prefix(6)

        var entryDates: Set<Date> = [now]
        for dueDate in dueDates {
            entryDates.insert(dueDate.addingTimeInterval(1))
            entryDates.insert(dueDate.addingTimeInterval(61))
        }
        let entries = entryDates.sorted().map { KidDoseWidgetEntry(date: $0, snapshots: snapshots) }

        // Reload a little after the last planned flip, or every few hours when idle. The app
        // also reloads the widget directly whenever a dose is logged or synced.
        let refreshAfter: Date
        if let lastDue = dueDates.last {
            refreshAfter = lastDue.addingTimeInterval(15 * 60)
        } else {
            refreshAfter = now.addingTimeInterval(4 * 3600)
        }

        completion(Timeline(entries: entries, policy: .after(refreshAfter)))
    }
}

// MARK: - Widget

struct KidDoseHomeWidget: Widget {
    let kind = "KidDoseHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KidDoseWidgetProvider()) { entry in
            KidDoseWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("KidDose")
        .description("Next dose times for your children.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Root View

struct KidDoseWidgetView: View {
    let entry: KidDoseWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularLockScreenView(entry: entry)
        case .accessoryRectangular:
            RectangularLockScreenView(entry: entry)
        case .accessoryInline:
            InlineLockScreenView(entry: entry)
        case .systemSmall:
            if let snapshot = mostUrgentSnapshot(in: entry.snapshots, at: entry.date) {
                SmallWidgetView(snapshot: snapshot, now: entry.date)
            } else {
                EmptyStateView()
            }
        default:
            if entry.snapshots.isEmpty {
                EmptyStateView()
            } else {
                MediumWidgetView(snapshots: entry.snapshots, now: entry.date)
            }
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "pills.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Add a child in KidDose")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Dose Status

private enum DoseStatus {
    case noDoses
    case skipped
    /// The window is open. Associated date is when it opened (nil when there is no timer).
    case ready(Date?)
    /// Open for more than a minute, matching the Home screen's "Overdue" badge.
    case overdue(Date)
    case waiting(Date)
}

private func doseStatus(for snapshot: WidgetChildSnapshot, medication: Medication, at now: Date) -> DoseStatus {
    if snapshot.isSessionEnded(for: medication) { return .skipped }
    guard snapshot.hasDoses(for: medication) else { return .noDoses }
    guard let next = snapshot.nextDate(for: medication) else { return .ready(nil) }
    if now < next { return .waiting(next) }
    return now.timeIntervalSince(next) < 60 ? .ready(next) : .overdue(next)
}

/// Lower is more urgent: overdue, then ready, then soonest countdown, then nothing to track.
private func urgencyScore(_ status: DoseStatus, at now: Date) -> TimeInterval {
    switch status {
    case .overdue:              return 0
    case .ready:                return 1
    case .waiting(let next):    return 2 + max(0, next.timeIntervalSince(now))
    case .skipped, .noDoses:    return .greatestFiniteMagnitude
    }
}

private func urgencyScore(_ snapshot: WidgetChildSnapshot, at now: Date) -> TimeInterval {
    Medication.allCases
        .map { urgencyScore(doseStatus(for: snapshot, medication: $0, at: now), at: now) }
        .min() ?? .greatestFiniteMagnitude
}

private func mostUrgentSnapshot(in snapshots: [WidgetChildSnapshot], at now: Date) -> WidgetChildSnapshot? {
    // `min(by:)` keeps the first child on ties, so the parent's ordering wins.
    snapshots.min { urgencyScore($0, at: now) < urgencyScore($1, at: now) }
}

private struct FocusedDose {
    let snapshot: WidgetChildSnapshot
    let medication: Medication
    let status: DoseStatus
}

/// The single most urgent child + medication pair, for the one-line Lock Screen families.
private func focusedDose(in snapshots: [WidgetChildSnapshot], at now: Date) -> FocusedDose? {
    var best: FocusedDose?
    var bestScore = TimeInterval.greatestFiniteMagnitude
    for snapshot in snapshots {
        for medication in Medication.allCases {
            let status = doseStatus(for: snapshot, medication: medication, at: now)
            let score = urgencyScore(status, at: now)
            if score < bestScore {
                bestScore = score
                best = FocusedDose(snapshot: snapshot, medication: medication, status: status)
            }
        }
    }
    return best
}

// MARK: - Small Widget (one child)

private struct SmallWidgetView: View {
    let snapshot: WidgetChildSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChildHeader(snapshot: snapshot, font: .subheadline.weight(.semibold), dotSize: 10)
            Divider()
            ForEach(Medication.allCases, id: \.self) { medication in
                MedRowView(
                    medication: medication,
                    status: doseStatus(for: snapshot, medication: medication, at: now),
                    now: now
                )
            }
            Spacer(minLength: 0)
            if let focus = focusedDose(in: [snapshot], at: now), case .waiting(let next) = focus.status {
                Text("\(focus.medication.displayName) at \(timeLabel(next))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium Widget (all children, up to 4)

private struct MediumWidgetView: View {
    let snapshots: [WidgetChildSnapshot]
    let now: Date

    private var displaySnapshots: [WidgetChildSnapshot] { Array(snapshots.prefix(4)) }

    var body: some View {
        if displaySnapshots.count == 1 {
            WideSingleChildView(snapshot: displaySnapshots[0], now: now)
        } else {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(displaySnapshots) { snapshot in
                    ChildCardView(snapshot: snapshot, now: now)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Medium widget with a single child: rows on the left, the most urgent countdown big on the right.
private struct WideSingleChildView: View {
    let snapshot: WidgetChildSnapshot
    let now: Date

    var body: some View {
        let focus = focusedDose(in: [snapshot], at: now)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ChildHeader(snapshot: snapshot, font: .subheadline.weight(.semibold), dotSize: 10)
                Divider()
                ForEach(Medication.allCases, id: \.self) { medication in
                    MedRowView(
                        medication: medication,
                        status: doseStatus(for: snapshot, medication: medication, at: now),
                        now: now
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let focus {
                VStack(alignment: .trailing, spacing: 2) {
                    StatusText(status: focus.status, now: now, tint: focus.medication.color)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(focusCaption(focus))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                .frame(width: 120, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func focusCaption(_ focus: FocusedDose) -> String {
        switch focus.status {
        case .waiting(let next):    return "\(focus.medication.displayName) at \(timeLabel(next))"
        case .ready, .overdue:      return "\(focus.medication.displayName) ready"
        case .skipped:              return "\(focus.medication.displayName) skipped"
        case .noDoses:              return "No doses yet"
        }
    }
}

// MARK: - Child Card (used in medium grid)

private struct ChildCardView: View {
    let snapshot: WidgetChildSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ChildHeader(snapshot: snapshot, font: .caption.weight(.semibold), dotSize: 8)
            ForEach(Medication.allCases, id: \.self) { medication in
                MedRowView(
                    medication: medication,
                    status: doseStatus(for: snapshot, medication: medication, at: now),
                    now: now
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ChildHeader: View {
    let snapshot: WidgetChildSnapshot
    let font: Font
    let dotSize: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color(from: snapshot.colorHex))
                .frame(width: dotSize, height: dotSize)
            Text(snapshot.name)
                .font(font)
                .lineLimit(1)
        }
    }
}

// MARK: - Medication Row

private struct MedRowView: View {
    let medication: Medication
    let status: DoseStatus
    let now: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: medication.iconName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(medication.color)
                .frame(width: 12)
            StatusText(status: status, now: now, tint: medication.color)
                .font(.caption2.monospacedDigit().weight(.medium))
                .lineLimit(1)
        }
    }
}

/// Status label shared by every family. Countdowns are live (`Text(timerInterval:)`),
/// and stop at 0:00 instead of counting up; the timeline entry at the due date then flips to "Ready".
private struct StatusText: View {
    let status: DoseStatus
    let now: Date
    let tint: Color

    var body: some View {
        switch status {
        case .noDoses:
            Text("—")
                .foregroundStyle(.secondary)
        case .skipped:
            Label("Skipped", systemImage: "forward.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.orange)
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
        case .overdue:
            Label("Overdue", systemImage: "exclamationmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red)
        case .waiting(let next):
            Text(timerInterval: min(now, next)...next, countsDown: true)
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Lock Screen: Circular

private struct CircularLockScreenView: View {
    let entry: KidDoseWidgetEntry

    var body: some View {
        let focus = focusedDose(in: entry.snapshots, at: entry.date)
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: focus?.medication.iconName ?? "pills.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                if let focus {
                    switch focus.status {
                    case .waiting(let next):
                        Text(timerInterval: min(entry.date, next)...next, countsDown: true)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                    case .ready, .overdue:
                        Text("Ready")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    case .skipped:
                        Text("Skip")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    case .noDoses:
                        Text("—")
                            .font(.caption2)
                    }
                } else {
                    Text("—")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Lock Screen: Rectangular

private struct RectangularLockScreenView: View {
    let entry: KidDoseWidgetEntry

    var body: some View {
        if let snapshot = mostUrgentSnapshot(in: entry.snapshots, at: entry.date) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "pills.fill")
                        .font(.caption2.weight(.semibold))
                    Text(snapshot.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .widgetAccentable()

                ForEach(Medication.allCases, id: \.self) { medication in
                    HStack(spacing: 4) {
                        Image(systemName: medication.iconName)
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 12)
                        Text(medication.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        AccessoryStatusText(
                            status: doseStatus(for: snapshot, medication: medication, at: entry.date),
                            now: entry.date
                        )
                        .font(.caption2.monospacedDigit().weight(.semibold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("KidDose")
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                Text("Add a child in the app")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Monochrome status for accessory families (the Lock Screen renders them tinted/vibrant).
private struct AccessoryStatusText: View {
    let status: DoseStatus
    let now: Date

    var body: some View {
        switch status {
        case .noDoses:
            Text("—").foregroundStyle(.secondary)
        case .skipped:
            Text("Skipped").foregroundStyle(.secondary)
        case .ready, .overdue:
            Text("Ready")
        case .waiting(let next):
            Text(timerInterval: min(now, next)...next, countsDown: true)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Lock Screen: Inline

private struct InlineLockScreenView: View {
    let entry: KidDoseWidgetEntry

    var body: some View {
        if let focus = focusedDose(in: entry.snapshots, at: entry.date) {
            let name = focus.snapshot.name.components(separatedBy: " ").first ?? focus.snapshot.name
            let medication = focus.medication.displayName
            switch focus.status {
            case .waiting(let next):
                Text("\(name) · \(medication) ") + Text(timerInterval: min(entry.date, next)...next, countsDown: true)
            case .ready, .overdue:
                Text("\(name) · \(medication) ready")
            case .skipped:
                Text("\(name) · \(medication) skipped")
            case .noDoses:
                Text("\(name) · No doses yet")
            }
        } else {
            Text("KidDose · Add a child")
        }
    }
}

// MARK: - Helpers

private func timeLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return date.formatted(.dateTime.hour().minute())
    }
    if calendar.isDateInTomorrow(date) {
        return "tomorrow \(date.formatted(.dateTime.hour().minute()))"
    }
    return date.formatted(.dateTime.month().day().hour().minute())
}

private func color(from hex: String) -> Color {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h = String(h.dropFirst()) }
    guard h.count == 6, let value = UInt64(h, radix: 16) else { return .accentColor }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
}
