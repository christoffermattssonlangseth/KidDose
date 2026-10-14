import Foundation
import SwiftData
import WidgetKit

/// App-side handling for `GiveDoseButtonIntent` (the widget extension has a no-op twin).
@MainActor
enum LockScreenDoseRouter {
    static func handleTap(childID: String, medication rawMedication: String) async {
        guard
            let container = KidDoseStore.container,
            let medication = Medication(rawValue: rawMedication)
        else { return }

        let context = container.mainContext
        let viewModel = KidDoseStore.viewModel
        viewModel.prepareStoredData(context: context)

        let children = (try? context.fetch(FetchDescriptor<Child>())) ?? []
        guard let child = children.first(where: { $0.stableID == childID }) else { return }

        // Same rules as the in-app button: only when the window is open and the
        // parent-set daily limit isn't reached. Overrides stay in the app.
        let limitReached = viewModel.dailyLimitStatus(for: medication, child: child)?.isReached ?? false
        guard
            !viewModel.isMedicationSessionEnded(for: medication, child: child),
            viewModel.canGiveDose(for: medication, child: child),
            !limitReached
        else {
            WidgetDataStore.writePendingConfirmation(nil)
            reloadSurfaces(viewModel: viewModel, context: context)
            return
        }

        if let pending = WidgetDataStore.readPendingConfirmation(),
           pending.matches(childID: childID, medication: rawMedication) {
            // Second tap: log it. logDose refreshes widgets, Watch and the Live Activity.
            WidgetDataStore.writePendingConfirmation(nil)
            viewModel.logDose(
                medication: medication,
                intervalHours: viewModel.currentInterval(for: medication, child: child),
                for: child,
                context: context
            )
            WidgetCenter.shared.reloadTimelines(ofKind: "KidDoseHomeWidget")
            return
        }

        // First tap: arm, show "Tap again to give", and reset when the window passes.
        WidgetDataStore.writePendingConfirmation(
            PendingDoseConfirmation(
                childID: childID,
                medication: rawMedication,
                expiresAt: Date.now.addingTimeInterval(PendingDoseConfirmation.window)
            )
        )
        reloadSurfaces(viewModel: viewModel, context: context)

        try? await Task.sleep(for: .seconds(PendingDoseConfirmation.window + 0.5))
        if WidgetDataStore.readPendingConfirmation() == nil {
            reloadSurfaces(viewModel: viewModel, context: context)
        }
    }

    private static func reloadSurfaces(viewModel: DoseViewModel, context: ModelContext) {
        WidgetCenter.shared.reloadTimelines(ofKind: "KidDoseHomeWidget")
        viewModel.refreshLiveActivity(context: context)
    }
}
