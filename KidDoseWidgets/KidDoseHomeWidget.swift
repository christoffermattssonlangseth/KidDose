import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct KidDoseWidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [WidgetChildSnapshot]
}

// MARK: - Timeline Provider

struct KidDoseWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> KidDoseWidgetEntry {
        KidDoseWidgetEntry(
            date: .now,
            snapshots: [
                WidgetChildSnapshot(
                    name: "Emma",
                    colorHex: "#FF6B35",
                    ibuprofenNextDate: Date.now.addingTimeInterval(5400),
                    paracetamolNextDate: nil,
                    ibuprofenHasDoses: true,
                    paracetamolHasDoses: true
                )
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (KidDoseWidgetEntry) -> Void) {
        completion(KidDoseWidgetEntry(date: .now, snapshots: WidgetDataStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KidDoseWidgetEntry>) -> Void) {
        let snapshots = WidgetDataStore.read()
        let entry = KidDoseWidgetEntry(date: .now, snapshots: snapshots)

        // Refresh at the soonest upcoming dose window, or in 15 minutes if nothing is pending.
        let nextUpdate = snapshots
            .flatMap { [$0.ibuprofenNextDate, $0.paracetamolNextDate] }
            .compactMap { $0 }
            .filter { $0 > .now }
            .min() ?? Date.now.addingTimeInterval(900)

        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Root View

struct KidDoseWidgetView: View {
    let entry: KidDoseWidgetEntry
    @Environment(\.widgetFamily) private var family

    /// Child with the most urgent upcoming dose (soonest next-allowed date, ready counts as 0).
    private var urgentSnapshot: WidgetChildSnapshot? {
        entry.snapshots.min { a, b in
            urgencyScore(a) < urgencyScore(b)
        }
    }

    var body: some View {
        if entry.snapshots.isEmpty {
            emptyView
        } else {
            switch family {
            case .systemSmall:
                SmallWidgetView(snapshot: urgentSnapshot ?? entry.snapshots[0])
            default:
                MediumWidgetView(snapshots: entry.snapshots)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "pills.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No children added")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Lower score = more urgent. Ready/overdue doses score 0, pending doses score their remaining seconds.
    private func urgencyScore(_ s: WidgetChildSnapshot) -> TimeInterval {
        let ibu = s.ibuprofenNextDate.map { max(0, $0.timeIntervalSince(.now)) } ?? 0
        let para = s.paracetamolNextDate.map { max(0, $0.timeIntervalSince(.now)) } ?? 0
        return min(ibu, para)
    }
}

// MARK: - Small Widget (one child)

private struct SmallWidgetView: View {
    let snapshot: WidgetChildSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color(from: snapshot.colorHex))
                    .frame(width: 10, height: 10)
                Text(snapshot.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Divider()
            MedRowView(
                iconName: "flame.fill",
                color: .orange,
                nextDate: snapshot.ibuprofenNextDate,
                hasDoses: snapshot.ibuprofenHasDoses
            )
            MedRowView(
                iconName: "cross.fill",
                color: Color(red: 0.10, green: 0.28, blue: 0.72),
                nextDate: snapshot.paracetamolNextDate,
                hasDoses: snapshot.paracetamolHasDoses
            )
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium Widget (all children, up to 4)

private struct MediumWidgetView: View {
    let snapshots: [WidgetChildSnapshot]

    private var displaySnapshots: [WidgetChildSnapshot] { Array(snapshots.prefix(4)) }

    var body: some View {
        if displaySnapshots.count == 1 {
            // Single child: full-width layout
            SmallWidgetView(snapshot: displaySnapshots[0])
        } else {
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(displaySnapshots) { snapshot in
                    ChildCardView(snapshot: snapshot)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Child Card (used in medium grid)

private struct ChildCardView: View {
    let snapshot: WidgetChildSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color(from: snapshot.colorHex))
                    .frame(width: 8, height: 8)
                Text(snapshot.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            MedRowView(
                iconName: "flame.fill",
                color: .orange,
                nextDate: snapshot.ibuprofenNextDate,
                hasDoses: snapshot.ibuprofenHasDoses
            )
            MedRowView(
                iconName: "cross.fill",
                color: Color(red: 0.10, green: 0.28, blue: 0.72),
                nextDate: snapshot.paracetamolNextDate,
                hasDoses: snapshot.paracetamolHasDoses
            )
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Medication Row

private struct MedRowView: View {
    let iconName: String
    let color: Color
    let nextDate: Date?
    let hasDoses: Bool

    private enum DoseStatus {
        case noDoses
        case ready
        case overdue(Date)
        case waiting(Date)
    }

    private var status: DoseStatus {
        guard hasDoses else { return .noDoses }
        guard let next = nextDate else { return .ready }
        return Date.now >= next ? .overdue(next) : .waiting(next)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 12)
            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .noDoses:
            Text("—")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .ready:
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Ready")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
        case .overdue:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Text("Overdue")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        case .waiting(let next):
            Text(timerInterval: Date.now...next, countsDown: true)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Hex Color Helper

private func color(from hex: String) -> Color {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h = String(h.dropFirst()) }
    guard h.count == 6, let value = UInt64(h, radix: 16) else { return .accentColor }
    let r = Double((value >> 16) & 0xFF) / 255
    let g = Double((value >> 8) & 0xFF) / 255
    let b = Double(value & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
}
