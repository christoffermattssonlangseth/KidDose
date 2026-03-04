import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct KidDoseComplicationEntry: TimelineEntry {
    let date: Date
    let snapshots: [WidgetChildSnapshot]
}

// MARK: - Timeline Provider

struct KidDoseComplicationProvider: TimelineProvider {

    func placeholder(in context: Context) -> KidDoseComplicationEntry {
        KidDoseComplicationEntry(date: .now, snapshots: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (KidDoseComplicationEntry) -> Void) {
        let snapshots = WidgetDataStore.read()
        completion(KidDoseComplicationEntry(date: .now, snapshots: snapshots))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KidDoseComplicationEntry>) -> Void) {
        let snapshots = WidgetDataStore.read()
        let now = Date.now
        let entry = KidDoseComplicationEntry(date: now, snapshots: snapshots)

        // Refresh at the next dose window so the complication stays current.
        let nextRefresh = nextDoseWindow(from: snapshots) ?? now.addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    /// Returns the earliest upcoming dose window across all snapshots.
    private func nextDoseWindow(from snapshots: [WidgetChildSnapshot]) -> Date? {
        let futureDates = snapshots.flatMap { s in
            [s.ibuprofenNextDate, s.paracetamolNextDate].compactMap { $0 }
        }
        .filter { $0 > .now }
        return futureDates.min()
    }
}

// MARK: - Urgency Scoring (mirrors home screen widget)

private func urgencyScore(for snapshot: WidgetChildSnapshot) -> Int {
    var score = 0
    if snapshot.ibuprofenHasDoses {
        if let next = snapshot.ibuprofenNextDate {
            if next <= .now { score += 2 } else { score += 1 }
        }
    }
    if snapshot.paracetamolHasDoses {
        if let next = snapshot.paracetamolNextDate {
            if next <= .now { score += 2 } else { score += 1 }
        }
    }
    return score
}

private func mostUrgentSnapshot(in snapshots: [WidgetChildSnapshot]) -> WidgetChildSnapshot? {
    snapshots.max(by: { urgencyScore(for: $0) < urgencyScore(for: $1) })
}

// MARK: - Complication Views

struct KidDoseComplication: Widget {
    let kind = "KidDoseComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KidDoseComplicationProvider()) { entry in
            KidDoseComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("KidDose")
        .description("Shows next dose status for your children.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Entry View (dispatches to family-specific views)

struct KidDoseComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KidDoseComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(entry: entry)
        case .accessoryRectangular:
            RectangularView(entry: entry)
        case .accessoryInline:
            InlineView(entry: entry)
        default:
            EmptyView()
        }
    }
}

// MARK: - Circular

private struct CircularView: View {
    let entry: KidDoseComplicationEntry

    var body: some View {
        let snapshot = mostUrgentSnapshot(in: entry.snapshots)
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: "pills.fill")
                    .font(.caption2.bold())
                if let snapshot {
                    if let soonest = soonestFutureDate(snapshot) {
                        Text(timerInterval: entry.date...soonest, countsDown: true)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.5)
                    } else {
                        Text("Ready")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func soonestFutureDate(_ snapshot: WidgetChildSnapshot) -> Date? {
        [snapshot.ibuprofenNextDate, snapshot.paracetamolNextDate]
            .compactMap { $0 }
            .filter { $0 > entry.date }
            .min()
    }
}

// MARK: - Rectangular

private struct RectangularView: View {
    let entry: KidDoseComplicationEntry

    var body: some View {
        let snapshot = mostUrgentSnapshot(in: entry.snapshots)
        VStack(alignment: .leading, spacing: 3) {
            if let snapshot {
                Text(snapshot.name)
                    .font(.caption2.bold())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text(statusText(date: snapshot.ibuprofenNextDate, hasDoses: snapshot.ibuprofenHasDoses, refDate: entry.date))
                        .font(.caption2)
                }

                HStack(spacing: 4) {
                    Image(systemName: "cross.fill")
                        .foregroundStyle(Color(red: 0.10, green: 0.28, blue: 0.72))
                        .font(.caption2)
                    Text(statusText(date: snapshot.paracetamolNextDate, hasDoses: snapshot.paracetamolHasDoses, refDate: entry.date))
                        .font(.caption2)
                }
            } else {
                Text("No children")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusText(date: Date?, hasDoses: Bool, refDate: Date) -> String {
        guard hasDoses || date != nil else { return "—" }
        guard let date else { return "Ready" }
        if date <= refDate { return "Ready" }
        let interval = date.timeIntervalSince(refDate)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

// MARK: - Inline

private struct InlineView: View {
    let entry: KidDoseComplicationEntry

    var body: some View {
        Text(inlineText)
    }

    private var inlineText: String {
        guard let snapshot = mostUrgentSnapshot(in: entry.snapshots) else {
            return "KidDose"
        }

        let name = snapshot.name.components(separatedBy: " ").first ?? snapshot.name

        // Check ibuprofen first (same urgency as widget).
        if snapshot.ibuprofenHasDoses {
            if let next = snapshot.ibuprofenNextDate, next > entry.date {
                let interval = next.timeIntervalSince(entry.date)
                let hours = Int(interval) / 3600
                let minutes = (Int(interval) % 3600) / 60
                let timeStr = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                return "\(name): Ibu \(timeStr)"
            } else {
                return "\(name): Ibu ready"
            }
        }

        if snapshot.paracetamolHasDoses {
            if let next = snapshot.paracetamolNextDate, next > entry.date {
                let interval = next.timeIntervalSince(entry.date)
                let hours = Int(interval) / 3600
                let minutes = (Int(interval) % 3600) / 60
                let timeStr = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                return "\(name): Para \(timeStr)"
            } else {
                return "\(name): Para ready"
            }
        }

        return "\(name): —"
    }
}
