import SwiftUI

struct DoseLogView: View {
    let childName: String
    let medication: Medication
    let intervalHours: Double

    @Environment(WatchSessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var result: DoseLogRequestResult? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: medication.iconName)
                .font(.title)
                .foregroundStyle(medication.color)

            Text("Give \(medication.displayName) to \(childName)?")
                .font(.footnote)
                .multilineTextAlignment(.center)

            if let result {
                Text(result.feedbackText)
                    .font(.footnote.bold())
                    .foregroundStyle(result.isSuccess ? .green : .red)
            }

            if result?.isSuccess != true {
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Confirm") {
                        let requestResult = sessionManager.requestDoseLog(
                            childName: childName,
                            medication: medication.rawValue,
                            intervalHours: intervalHours
                        )
                        result = requestResult
                        if requestResult.isSuccess {
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(medication.color)
                }
            }
        }
        .padding()
    }
}
