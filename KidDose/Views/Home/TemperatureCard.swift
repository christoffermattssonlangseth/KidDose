import SwiftUI
import SwiftData
import Charts

/// Latest temperature / symptoms for a child, with a quick way to add a reading.
struct TemperatureCard: View {
    let child: Child
    @State private var showAddSheet = false

    private var readings: [TemperatureLog] {
        child.temperatureReadings.sorted { $0.timestamp < $1.timestamp }
    }

    private var latest: TemperatureLog? { readings.last }

    /// Readings with a temperature from the last 24 hours, for the sparkline.
    private var recentTemperatures: [TemperatureLog] {
        let start = Date.now.addingTimeInterval(-24 * 3600)
        return readings.filter { $0.timestamp >= start && $0.celsius != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "thermometer.medium")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(latest?.isFever == true ? .red : .secondary)
                    }
                Text("Temperature & Symptoms")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .kidDoseSecondaryButton()
                .controlSize(.small)
            }

            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let celsius = latest.celsius {
                        Text(TemperatureFormat.display(celsius))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(latest.isFever ? .red : .primary)
                            .contentTransition(.numericText())
                        if latest.isFever {
                            StatusPill(title: "Fever", systemImage: "flame.fill", tint: .red)
                        }
                    } else {
                        Text("Symptoms noted")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text(latest.timestamp, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let symptoms = latest.symptoms {
                    Text(symptoms)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if recentTemperatures.count >= 2 {
                    TemperatureSparkline(readings: recentTemperatures)
                        .frame(height: 54)
                }
            } else {
                Text("Log fevers and symptoms next to doses. They're included in the doctor summary in History.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .kidDoseCardSurface(cornerRadius: 22)
        .sheet(isPresented: $showAddSheet) {
            AddReadingSheet(child: child, suggestedCelsius: latest?.celsius)
                .presentationDetents([.large])
        }
    }
}

// MARK: - Sparkline

private struct TemperatureSparkline: View {
    let readings: [TemperatureLog]

    var body: some View {
        Chart {
            RuleMark(y: .value("Fever", TemperatureFormat.fromCelsius(38.0)))
                .foregroundStyle(Color.red.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(readings) { reading in
                if let celsius = reading.celsius {
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Temperature", TemperatureFormat.fromCelsius(celsius))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.secondary)
                    PointMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Temperature", TemperatureFormat.fromCelsius(celsius))
                    )
                    .symbolSize(18)
                    .foregroundStyle(reading.isFever ? Color.red : Color.secondary)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("Temperature over the last 24 hours")
    }
}

// MARK: - Add Reading

struct AddReadingSheet: View {
    let child: Child
    let suggestedCelsius: Double?

    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var includeTemperature = true
    /// Selected value in tenths of the display unit (e.g. 384 = 38.4 °C).
    @State private var tenths: Int
    @State private var selectedSymptoms: Set<String> = []
    @State private var notes = ""
    @State private var timestamp = Date.now

    private static let commonSymptoms = [
        "Cough", "Sore throat", "Earache", "Runny nose", "Headache",
        "Vomiting", "Diarrhea", "Rash", "Tired", "Not eating"
    ]

    init(child: Child, suggestedCelsius: Double?) {
        self.child = child
        self.suggestedCelsius = suggestedCelsius
        let start = TemperatureFormat.fromCelsius(suggestedCelsius ?? 38.0)
        _tenths = State(initialValue: Int((start * 10).rounded()))
    }

    private var range: ClosedRange<Int> {
        TemperatureFormat.usesFahrenheit ? 950...1076 : 350...420
    }

    private var symptomsText: String? {
        var parts = Self.commonSymptoms.filter { selectedSymptoms.contains($0) }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private var canSave: Bool { includeTemperature || symptomsText != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Temperature", isOn: $includeTemperature.animation())
                    if includeTemperature {
                        Picker("Temperature", selection: $tenths) {
                            ForEach(range, id: \.self) { value in
                                Text(String(format: "%.1f %@", Double(value) / 10, TemperatureFormat.unitSymbol))
                                    .monospacedDigit()
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 140)
                    }
                }

                Section("Symptoms") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(Self.commonSymptoms, id: \.self) { symptom in
                            let isOn = selectedSymptoms.contains(symptom)
                            Button {
                                if isOn {
                                    selectedSymptoms.remove(symptom)
                                } else {
                                    selectedSymptoms.insert(symptom)
                                }
                            } label: {
                                Text(symptom)
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(isOn ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                                    .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    .sensoryFeedback(.selection, trigger: selectedSymptoms)

                    TextField("Other notes", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    DatePicker("Time", selection: $timestamp, in: ...Date.now)
                } footer: {
                    Text("Saved for \(child.name). Your partner sees it too if family sharing is on.")
                }
            }
            .navigationTitle("New Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let celsius = includeTemperature
                            ? TemperatureFormat.toCelsius(Double(tenths) / 10)
                            : nil
                        viewModel.addReading(
                            celsius: celsius,
                            symptoms: symptomsText,
                            timestamp: timestamp,
                            for: child,
                            context: context
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
