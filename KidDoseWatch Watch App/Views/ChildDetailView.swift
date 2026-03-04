import SwiftUI

struct ChildDetailView: View {
    let snapshot: WidgetChildSnapshot
    @Environment(WatchSessionManager.self) private var sessionManager

    @State private var logTarget: MedicationLogTarget? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                medicationCard(
                    medication: .ibuprofen,
                    nextDate: snapshot.ibuprofenNextDate,
                    hasDoses: snapshot.ibuprofenHasDoses
                )
                medicationCard(
                    medication: .paracetamol,
                    nextDate: snapshot.paracetamolNextDate,
                    hasDoses: snapshot.paracetamolHasDoses
                )
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(snapshot.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $logTarget) { target in
            DoseLogView(
                childName: snapshot.name,
                medication: target.medication,
                intervalHours: target.medication.intervalHours
            )
            .environment(sessionManager)
        }
    }

    @ViewBuilder
    private func medicationCard(medication: Medication, nextDate: Date?, hasDoses: Bool) -> some View {
        let isReady = hasDoses && (nextDate == nil || nextDate! <= .now)
        let hasAny = hasDoses || nextDate != nil

        HStack(spacing: 8) {
            Image(systemName: medication.iconName)
                .foregroundStyle(medication.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(medication.displayName)
                    .font(.footnote.bold())

                if isReady {
                    Text("Ready")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if let date = nextDate, date > .now {
                    Text(countdownString(until: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if !hasAny {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isReady {
                Button("Give") {
                    logTarget = MedicationLogTarget(medication: medication)
                }
                .buttonStyle(.borderedProminent)
                .tint(medication.color)
                .font(.caption2.bold())
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func countdownString(until date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "Ready" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Log Target

private struct MedicationLogTarget: Identifiable {
    let id = UUID()
    let medication: Medication
}
