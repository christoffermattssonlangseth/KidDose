import AppIntents
import Foundation
import SwiftData

// MARK: - Parameters

enum MedicationAppEnum: String, AppEnum {
    case ibuprofen
    case paracetamol

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Medication"
    static let caseDisplayRepresentations: [MedicationAppEnum: DisplayRepresentation] = [
        .ibuprofen: DisplayRepresentation(title: "Ibuprofen", image: .init(systemName: "flame.fill")),
        .paracetamol: DisplayRepresentation(title: "Paracetamol", image: .init(systemName: "cross.fill"))
    ]

    var medication: Medication {
        switch self {
        case .ibuprofen: return .ibuprofen
        case .paracetamol: return .paracetamol
        }
    }
}

struct ChildEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Child"
    static let defaultQuery = ChildEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ChildEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ChildEntity] {
        IntentData.children()
            .filter { identifiers.contains($0.stableID) }
            .map { ChildEntity(id: $0.stableID, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ChildEntity] {
        IntentData.children().map { ChildEntity(id: $0.stableID, name: $0.name) }
    }
}

@MainActor
private enum IntentData {
    static func children() -> [Child] {
        guard let context = KidDoseStore.container?.mainContext else { return [] }
        KidDoseStore.viewModel.prepareStoredData(context: context)
        let all = (try? context.fetch(FetchDescriptor<Child>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return KidDoseStore.viewModel.visibleChildrenForCurrentFamily(all)
    }

    static func child(for entity: ChildEntity) -> Child? {
        children().first { $0.stableID == entity.id }
    }
}

// MARK: - Give Dose

struct GiveDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Give Dose"
    static let description = IntentDescription(
        "Log a dose of ibuprofen or paracetamol for a child. KidDose asks you to confirm and won't log a dose that isn't due yet."
    )

    @Parameter(title: "Child")
    var child: ChildEntity

    @Parameter(title: "Medication")
    var medication: MedicationAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Give \(\.$medication) to \(\.$child)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = KidDoseStore.container?.mainContext else {
            return .result(dialog: "KidDose couldn't open its data. Open the app and try again.")
        }
        guard let child = IntentData.child(for: self.child) else {
            return .result(dialog: "I couldn't find that child in KidDose.")
        }

        let viewModel = KidDoseStore.viewModel
        let medication = self.medication.medication
        let name = medication.displayName.lowercased()

        // Same rules as the app's button. Overrides stay in the app, where the full warning is shown.
        if let next = viewModel.nextDoseDate(for: medication, child: child) {
            let time = next.formatted(date: .omitted, time: .shortened)
            return .result(dialog: "\(child.name) can't have \(name) yet. The next dose is allowed at \(time).")
        }
        if let limit = viewModel.dailyLimitStatus(for: medication, child: child), limit.isReached {
            return .result(
                dialog: "\(child.name) has had \(limit.given) of \(limit.limit) \(name) doses in 24 hours. Open KidDose if your doctor advised another."
            )
        }

        let interval = viewModel.currentInterval(for: medication, child: child)
        try await requestConfirmation(
            result: .result(dialog: "Give \(name) to \(child.name) now? The next dose will be due in \(Int(interval)) hours.")
        )

        viewModel.logDose(medication: medication, intervalHours: interval, for: child, context: context)
        let next = Date.now.addingTimeInterval(interval * 3600).formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Logged \(name) for \(child.name). The next dose is allowed at \(next).")
    }
}

// MARK: - Next Dose

struct NextDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Dose"
    static let description = IntentDescription("Hear when each child can have their next dose.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let children = IntentData.children()
        guard !children.isEmpty else {
            return .result(dialog: "There are no children in KidDose yet.")
        }

        let viewModel = KidDoseStore.viewModel
        var sentences: [String] = []
        for child in children {
            for medication in Medication.allCases {
                guard
                    !viewModel.isMedicationSessionEnded(for: medication, child: child),
                    viewModel.latestDoseInCurrentCycle(for: medication, child: child) != nil
                else { continue }
                let name = medication.displayName.lowercased()
                if let next = viewModel.nextDoseDate(for: medication, child: child) {
                    sentences.append("\(child.name) can have \(name) at \(next.formatted(date: .omitted, time: .shortened)).")
                } else {
                    sentences.append("\(child.name) can have \(name) now.")
                }
            }
        }

        if sentences.isEmpty {
            return .result(dialog: "No doses are being tracked right now.")
        }
        return .result(dialog: "\(sentences.joined(separator: " "))")
    }
}

// MARK: - Siri Phrases

struct KidDoseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GiveDoseIntent(),
            phrases: [
                "Give \(\.$medication) in \(.applicationName)",
                "Log \(\.$medication) in \(.applicationName)",
                "Log a dose in \(.applicationName)"
            ],
            shortTitle: "Give Dose",
            systemImageName: "pills.fill"
        )
        AppShortcut(
            intent: NextDoseIntent(),
            phrases: [
                "When is the next dose in \(.applicationName)",
                "Next dose in \(.applicationName)"
            ],
            shortTitle: "Next Dose",
            systemImageName: "clock"
        )
    }
}
