import SwiftUI

/// A large card showing one medication's status for the selected child, with a live countdown.
struct MedicationCard: View {
    let medication: Medication
    let child: Child
    @Environment(DoseViewModel.self) private var viewModel
    @Environment(\.modelContext) private var context

    @State private var feedbackTrigger: Bool = false

    var canGive: Bool { viewModel.canGiveDose(for: medication, child: child) }
    var nextDate: Date? { viewModel.nextDoseDate(for: medication, child: child) }
    var lastDose: DoseLog? { child.lastDose(for: medication) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack {
                Image(systemName: medication.iconName)
                    .font(.title2)
                    .foregroundStyle(medication.color)
                Text(medication.displayName)
                    .font(.title3.bold())
                Spacer()
                if canGive {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Divider()

            // Last dose info
            if let last = lastDose {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last dose")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(last.relativeTimestamp)
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("by")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(last.givenBy)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                }
            } else {
                Text("No doses yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Live countdown
            if let next = nextDate {
                CountdownView(targetDate: next, medication: medication)
            }

            // Give Dose button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    feedbackTrigger.toggle()
                }
                viewModel.logDose(medication: medication, for: child, context: context)
            } label: {
                Label("Give Dose", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(canGive ? medication.color : .gray)
            .disabled(!canGive)
            .sensoryFeedback(.impact, trigger: feedbackTrigger)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 4)
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
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(medication.color)
                    Text(formattedCountdown(remaining))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(medication.color)
                    Text("until next dose")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
}
