import SwiftUI

// MARK: - Full Schedule

struct FullScheduleView: View {
    @Environment(DoseViewModel.self) private var viewModel
    let child: Child

    @State private var dosesPerMedication = 12
    @State private var referenceDate = Date.now

    private var schedule: [ScheduledDose] {
        viewModel.projectedSchedule(
            for: child,
            dosesPerMedication: dosesPerMedication,
            from: referenceDate
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $dosesPerMedication, in: 4...36, step: 2) {
                        Text("Future doses per medication: \(dosesPerMedication)")
                    }
                } footer: {
                    Text("Schedule assumes each medication is given exactly on time using the latest interval.")
                }

                if schedule.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No schedule yet",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("Log at least one dose to generate a forward schedule.")
                        )
                    }
                } else {
                    Section("Upcoming Timeline") {
                        ForEach(schedule) { item in
                            FullScheduleRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("\(child.name)'s Schedule")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FullScheduleRow: View {
    let item: ScheduledDose

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(item.medication.color.opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: item.medication.iconName)
                        .foregroundStyle(item.medication.color)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.medication.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(item.nextDate, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.nextDate, style: .relative)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(item.medication.color)
                Text("every \(Int(item.intervalHours))h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
