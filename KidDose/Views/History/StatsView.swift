import SwiftUI
import Charts

/// Plain copies of what the Stats charts need, so the screen can be rendered and tested
/// without a SwiftData store.
struct StatsData {
    struct Dose {
        let id: String
        let timestamp: Date
        let medication: Medication
        let intervalHours: Double
    }

    struct Reading {
        let id: String
        let timestamp: Date
        let celsius: Double
    }

    struct ChildSeries {
        let name: String
        let color: Color
        let doses: [Dose]
        let readings: [Reading]
    }

    let children: [ChildSeries]
}

extension StatsData {
    init(children: [Child]) {
        self.children = children.map { child in
            ChildSeries(
                name: child.name,
                color: child.tintColor,
                doses: child.doses.compactMap { dose in
                    guard let medication = dose.medicationEnum else { return nil }
                    return Dose(
                        id: String(describing: dose.persistentModelID),
                        timestamp: dose.timestamp,
                        medication: medication,
                        intervalHours: dose.usedIntervalHours > 0 ? dose.usedIntervalHours : medication.intervalHours
                    )
                },
                readings: child.temperatureReadings.compactMap { reading in
                    guard let celsius = reading.celsius else { return nil }
                    return Reading(id: String(describing: reading.persistentModelID), timestamp: reading.timestamp, celsius: celsius)
                }
            )
        }
    }
}

/// Charts of doses and temperature, one child at a time.
struct StatsView: View {
    let data: StatsData

    @State private var selectedChild: Int

    /// `initialChild` is the child History is filtered to, if any.
    init(data: StatsData, initialChild: String? = nil) {
        self.data = data
        _selectedChild = State(initialValue: data.children.firstIndex { $0.name == initialChild } ?? 0)
    }

    private var children: [StatsData.ChildSeries] {
        data.children.indices.contains(selectedChild) ? [data.children[selectedChild]] : []
    }

    @State private var range: StatsRange = .threeDays
    @State private var selectedTemperatureDate: Date?
    @State private var selectedDay: Date?

    enum StatsRange: Int, CaseIterable, Identifiable {
        case threeDays = 3, sevenDays = 7, thirtyDays = 30
        var id: Int { rawValue }
        var title: String { "\(rawValue) days" }
    }

    private struct TemperaturePoint: Identifiable {
        let id: String
        let date: Date
        /// In the user's display unit.
        let value: Double
        let isFever: Bool
    }

    private struct DoseSpan: Identifiable {
        let id: String
        let given: Date
        let medication: Medication
    }

    private struct DayCount: Identifiable {
        var id: String { "\(day.timeIntervalSince1970)-\(medication.rawValue)" }
        let day: Date
        let medication: Medication
        let count: Int
    }

    // MARK: Data

    private var calendar: Calendar { .current }
    private var now: Date { .now }
    private var start: Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: now)!)
    }
    private var temperaturePoints: [TemperaturePoint] {
        children.flatMap { child in
            child.readings.compactMap { reading -> TemperaturePoint? in
                guard reading.timestamp >= start else { return nil }
                return TemperaturePoint(
                    id: reading.id,
                    date: reading.timestamp,
                    value: TemperatureFormat.fromCelsius(reading.celsius),
                    isFever: reading.celsius >= 38.0
                )
            }
        }
        .sorted { $0.date < $1.date }
    }

    private var doseSpans: [DoseSpan] {
        children.flatMap { child in
            child.doses.compactMap { dose -> DoseSpan? in
                guard dose.timestamp >= start else { return nil }
                return DoseSpan(id: dose.id, given: dose.timestamp, medication: dose.medication)
            }
        }
        .sorted { $0.given < $1.given }
    }

    private var dayCounts: [DayCount] {
        var counts: [Date: [Medication: Int]] = [:]
        for span in doseSpans {
            counts[calendar.startOfDay(for: span.given), default: [:]][span.medication, default: 0] += 1
        }
        return counts.flatMap { day, byMedication in
            byMedication.map { DayCount(day: day, medication: $0.key, count: $0.value) }
        }
        .sorted { ($0.day, $0.medication.rawValue) < ($1.day, $1.medication.rawValue) }
    }

    private var medicationColors: KeyValuePairs<String, Color> {
        [Medication.ibuprofen.displayName: Medication.ibuprofen.color,
         Medication.paracetamol.displayName: Medication.paracetamol.color]
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            content
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The screen without its scroll view, which also lets tests render it to an image.
    var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                if data.children.count > 1 {
                    childPicker
                }

                Picker("Range", selection: $range) {
                    ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                summaryRow

                if doseSpans.isEmpty && temperaturePoints.isEmpty {
                    ContentUnavailableView(
                        "Nothing in the last \(range.title)",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Doses and temperatures you log show up here.")
                    )
                    .padding(.top, 24)
                } else {
                    temperatureCard
                    if !doseSpans.isEmpty {
                        dosesPerDayCard
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.snappy, value: range)
            .animation(.snappy, value: selectedChild)
    }

    private var childPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(data.children.indices, id: \.self) { index in
                    let child = data.children[index]
                    SelectableChip(
                        label: child.name,
                        isSelected: index == selectedChild,
                        tint: child.color
                    ) {
                        selectedChild = index
                        selectedTemperatureDate = nil
                        selectedDay = nil
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedChild)
    }

    // MARK: Summary

    private var summaryRow: some View {
        let fevers = temperaturePoints.filter(\.isFever).count
        let highest = temperaturePoints.map(\.value).max()
        return HStack(spacing: 10) {
            statTile(title: "Doses", value: "\(doseSpans.count)")
            statTile(
                title: "Highest",
                value: highest.map { String(format: "%.1f%@", $0, TemperatureFormat.unitSymbol) } ?? "–"
            )
            statTile(title: "Fever readings", value: "\(fevers)")
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .kidDoseCardSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: Temperature & doses

    /// Temperature line with each dose marked along the bottom edge, so it's easy to see
    /// how the fever moved after a dose.
    private var temperatureCard: some View {
        let values = temperaturePoints.map(\.value)
        let fever = TemperatureFormat.fromCelsius(38.0)
        let step: Double = TemperatureFormat.usesFahrenheit ? 2 : 1
        let low = (min(values.min() ?? fever, TemperatureFormat.fromCelsius(36.5)) / step).rounded(.down) * step - step / 2
        let high = (max(values.max() ?? fever, TemperatureFormat.fromCelsius(39.5)) / step).rounded(.up) * step
        // Dose markers sit in the half-step band below the lowest gridline.
        let doseBand = low + step / 4
        let selectedDate = selectedTemperatureDate
        let selected = nearestTemperature(to: selectedDate)
        let lastDose = selectedDate.flatMap { date in doseSpans.last { $0.given <= date } }
        let medications = Medication.allCases.filter { med in doseSpans.contains { $0.medication == med } }

        return card(
            title: doseSpans.isEmpty ? "Temperature" : "Temperature & doses",
            subtitle: doseSpans.isEmpty
                ? "Dashed line: fever, \(TemperatureFormat.display(38.0))"
                : "Dots along the bottom are doses. Dashed line: fever, \(TemperatureFormat.display(38.0))"
        ) {
            Chart {
                RuleMark(y: .value("Fever", fever))
                    .foregroundStyle(Color.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                ForEach(temperaturePoints) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Temperature", point.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Color.primary.opacity(0.75))

                    PointMark(x: .value("Time", point.date), y: .value("Temperature", point.value))
                        .symbolSize(point.isFever ? 50 : 30)
                        .foregroundStyle(point.isFever ? Color.red : Color.primary.opacity(0.75))
                }

                ForEach(doseSpans) { dose in
                    PointMark(x: .value("Dose", dose.given), y: .value("Temperature", doseBand))
                        .symbol(.circle)
                        .symbolSize(60)
                        .foregroundStyle(dose.medication.color)
                }

                if let selectedDate, selected != nil || lastDose != nil {
                    RuleMark(x: .value("Selected", selected?.date ?? selectedDate))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            calloutLabel(
                                selected.map { TemperatureFormat.display(TemperatureFormat.toCelsius($0.value)) + " at "
                                    + $0.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "No temperature",
                                detail: lastDose.map { "Last dose: \($0.medication.displayName) "
                                    + $0.given.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "No dose before this"
                            )
                        }
                }
            }
            .chartXScale(domain: start...now)
            .chartYScale(domain: low...high)
            .chartYAxis {
                AxisMarks(values: .stride(by: step)) { value in
                    if let number = value.as(Double.self), number >= low + step / 2 {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
            }
            .chartXAxis { timeAxis }
            .chartXSelection(value: $selectedTemperatureDate)
            .frame(height: 230)
            .accessibilityLabel("Temperature and doses over the last \(range.title)")

            if !medications.isEmpty {
                HStack(spacing: 14) {
                    ForEach(medications, id: \.self) { medication in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(medication.color)
                                .frame(width: 8, height: 8)
                            Text(medication.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func nearestTemperature(to date: Date?) -> TemperaturePoint? {
        guard let date else { return nil }
        // Only snap to a reading within 3 hours, so tapping between readings shows doses only.
        return temperaturePoints
            .filter { abs($0.date.timeIntervalSince(date)) < 3 * 3600 }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // MARK: Doses per day

    private var dosesPerDayCard: some View {
        let maxCount = dayCounts.map(\.count).max() ?? 1
        let selectedCounts = selectedDay.map { day in
            dayCounts.filter { calendar.isDate($0.day, inSameDayAs: day) }
        } ?? []

        return card(title: "Doses per day", subtitle: "Calendar days") {
            Chart {
                ForEach(dayCounts) { count in
                    BarMark(
                        x: .value("Day", count.day, unit: .day),
                        y: .value("Doses", count.count)
                    )
                    .foregroundStyle(by: .value("Medication", count.medication.displayName))
                    .position(by: .value("Medication", count.medication.displayName))
                    .cornerRadius(4)
                }

                if let day = selectedDay, !selectedCounts.isEmpty {
                    RuleMark(x: .value("Selected", day, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                        .zIndex(-1)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            calloutLabel(
                                selectedCounts
                                    .sorted { $0.medication.rawValue < $1.medication.rawValue }
                                    .map { "\($0.medication.displayName) \($0.count)" }
                                    .joined(separator: " · "),
                                detail: day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
                            )
                        }
                }
            }
            .chartForegroundStyleScale(medicationColors)
            .chartXScale(domain: start...calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!)
            .chartYScale(domain: 0...(maxCount + 1))
            .chartYAxis {
                AxisMarks(values: .stride(by: maxCount > 6 ? 2 : 1))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .thirtyDays ? 7 : 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).day(), centered: true)
                }
            }
            .chartXSelection(value: $selectedDay)
            .frame(height: 190)
            .accessibilityLabel("Doses per day over the last \(range.title)")
        }
    }

    // MARK: Pieces

    private var timeAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: range == .thirtyDays ? 7 : 1)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.weekday(.abbreviated).day())
        }
    }

    private func calloutLabel(_ value: String, detail: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func card<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .kidDoseCardSurface(cornerRadius: 18)
    }
}
