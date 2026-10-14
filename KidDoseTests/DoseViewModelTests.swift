import XCTest
import SwiftData
@testable import KidDose

@MainActor
final class DoseViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var viewModel: DoseViewModel!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: Child.self, DoseLog.self, TemperatureLog.self, configurations: config)
        context = container.mainContext
        viewModel = DoseViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        context = nil
        container = nil
    }

    // MARK: Helpers

    private func makeChild(_ name: String = "Emma") -> Child {
        let child = Child(name: name, colorHex: "#FF6B6B")
        context.insert(child)
        return child
    }

    @discardableResult
    private func addDose(
        _ medication: Medication,
        hoursAgo: Double,
        interval: Double = 0,
        to child: Child
    ) -> DoseLog {
        let dose = DoseLog(
            medication: medication,
            intervalHours: interval,
            timestamp: Date.now.addingTimeInterval(-hoursAgo * 3600),
            givenBy: "Test",
            child: child
        )
        context.insert(dose)
        try? context.save()
        return dose
    }

    // MARK: Timing

    func testNoDosesMeansCanGive() {
        let child = makeChild()
        XCTAssertNil(viewModel.nextAllowedDate(for: .ibuprofen, child: child))
        XCTAssertTrue(viewModel.canGiveDose(for: .ibuprofen, child: child))
    }

    func testNextAllowedUsesTheDosesOwnInterval() throws {
        let child = makeChild()
        let dose = addDose(.ibuprofen, hoursAgo: 1, interval: 6, to: child)
        let next = try XCTUnwrap(viewModel.nextAllowedDate(for: .ibuprofen, child: child))
        XCTAssertEqual(next.timeIntervalSince(dose.timestamp), 6 * 3600, accuracy: 1)
        XCTAssertFalse(viewModel.canGiveDose(for: .ibuprofen, child: child))
    }

    func testLegacyZeroIntervalFallsBackToDefault() throws {
        let child = makeChild()
        let dose = addDose(.paracetamol, hoursAgo: 1, to: child)
        dose.usedIntervalHours = 0
        let next = try XCTUnwrap(viewModel.nextAllowedDate(for: .paracetamol, child: child))
        XCTAssertEqual(next.timeIntervalSince(dose.timestamp), Medication.paracetamol.intervalHours * 3600, accuracy: 1)
    }

    func testMedicationsAreTrackedSeparately() {
        let child = makeChild()
        addDose(.ibuprofen, hoursAgo: 1, interval: 8, to: child)
        XCTAssertFalse(viewModel.canGiveDose(for: .ibuprofen, child: child))
        XCTAssertTrue(viewModel.canGiveDose(for: .paracetamol, child: child))
    }

    func testCanGiveOnceIntervalHasPassed() {
        let child = makeChild()
        addDose(.paracetamol, hoursAgo: 7, interval: 6, to: child)
        XCTAssertTrue(viewModel.canGiveDose(for: .paracetamol, child: child))
        XCTAssertNil(viewModel.nextDoseDate(for: .paracetamol, child: child))
    }

    // MARK: Courses and skipping

    func testNewCycleIgnoresEarlierDoses() {
        let child = makeChild()
        addDose(.ibuprofen, hoursAgo: 2, interval: 8, to: child)
        child.setCycleStartAt(.now, for: .ibuprofen)
        XCTAssertNil(viewModel.latestDoseInCurrentCycle(for: .ibuprofen, child: child))
        XCTAssertTrue(viewModel.canGiveDose(for: .ibuprofen, child: child))
    }

    func testSkippedCourseStopsTheTimerUntilANewDose() {
        let child = makeChild()
        addDose(.ibuprofen, hoursAgo: 2, interval: 8, to: child)
        child.setSessionEndedAt(.now, for: .ibuprofen)
        XCTAssertTrue(viewModel.isMedicationSessionEnded(for: .ibuprofen, child: child))
        XCTAssertNil(viewModel.nextAllowedDate(for: .ibuprofen, child: child))

        // A dose after the skip resumes tracking.
        addDose(.ibuprofen, hoursAgo: -0.01, interval: 8, to: child)
        XCTAssertFalse(viewModel.isMedicationSessionEnded(for: .ibuprofen, child: child))
        XCTAssertNotNil(viewModel.nextAllowedDate(for: .ibuprofen, child: child))
    }

    func testUpcomingDosesAreSortedSoonestFirst() {
        let child = makeChild()
        addDose(.ibuprofen, hoursAgo: 1, interval: 8, to: child)    // due in 7 h
        addDose(.paracetamol, hoursAgo: 1, interval: 6, to: child)  // due in 5 h
        let upcoming = viewModel.upcomingDoses(for: [child])
        XCTAssertEqual(upcoming.map(\.medication), [.paracetamol, .ibuprofen])
    }

    // MARK: Daily limits

    func testNoLimitSetMeansNoStatus() {
        let child = makeChild()
        addDose(.paracetamol, hoursAgo: 1, to: child)
        XCTAssertNil(viewModel.dailyLimitStatus(for: .paracetamol, child: child))
    }

    func testDailyLimitCountsOnlyTheLast24Hours() throws {
        let child = makeChild()
        child.setMaxDailyDoses(3, for: .paracetamol)
        addDose(.paracetamol, hoursAgo: 30, to: child)
        addDose(.paracetamol, hoursAgo: 18, to: child)
        addDose(.paracetamol, hoursAgo: 12, to: child)
        let status = try XCTUnwrap(viewModel.dailyLimitStatus(for: .paracetamol, child: child))
        XCTAssertEqual(status.given, 2)
        XCTAssertFalse(status.isReached)

        addDose(.paracetamol, hoursAgo: 6, to: child)
        let reached = try XCTUnwrap(viewModel.dailyLimitStatus(for: .paracetamol, child: child))
        XCTAssertTrue(reached.isReached)
        XCTAssertNotNil(reached.resetsAt)
    }

    func testSettingLimitToZeroClearsIt() {
        let child = makeChild()
        child.setMaxDailyDoses(4, for: .ibuprofen)
        child.setMaxDailyDoses(0, for: .ibuprofen)
        XCTAssertNil(child.maxDailyDoses(for: .ibuprofen))
    }

    // MARK: Intervals and identity

    func testCurrentIntervalFollowsLatestDose() {
        let child = makeChild()
        XCTAssertEqual(viewModel.currentInterval(for: .ibuprofen, child: child), 8)
        addDose(.ibuprofen, hoursAgo: 1, interval: 6, to: child)
        XCTAssertEqual(viewModel.currentInterval(for: .ibuprofen, child: child), 6)
    }

    func testNotificationIDUsesStableIDNotName() {
        let child = makeChild("Emma")
        let id = child.notificationID(for: .ibuprofen)
        child.name = "Emma B"
        XCTAssertEqual(child.notificationID(for: .ibuprofen), id)
        XCTAssertFalse(id.contains("Emma"))
    }

    func testPrepareStoredDataBackfillsMissingIDs() {
        let child = makeChild()
        child.uid = nil
        viewModel.prepareStoredData(context: context)
        XCTAssertNotNil(child.uid)
    }

    func testAmountIsCapturedAndTrimmed() {
        let child = makeChild()
        let dose = DoseLog(medication: .ibuprofen, givenBy: "Test", child: child, amount: "  6 ml ")
        XCTAssertEqual(dose.amount, "6 ml")
        let empty = DoseLog(medication: .ibuprofen, givenBy: "Test", child: child, amount: "   ")
        XCTAssertNil(empty.amount)
    }
}

final class WidgetSnapshotCompatibilityTests: XCTestCase {
    /// Snapshots written by older app builds lack the newer keys and must still decode.
    func testDecodesSnapshotFromOlderBuild() throws {
        let json = """
        [{"name":"Emma","colorHex":"#FF6B6B","ibuprofenHasDoses":true,"paracetamolHasDoses":false}]
        """
        let snapshots = try JSONDecoder().decode([WidgetChildSnapshot].self, from: Data(json.utf8))
        XCTAssertEqual(snapshots.first?.id, "Emma")
        XCTAssertEqual(snapshots.first?.intervalHours(for: .ibuprofen), 8)
        XCTAssertFalse(snapshots.first?.isSessionEnded(for: .ibuprofen) ?? true)
        XCTAssertFalse(snapshots.first?.isLimitReached(for: .paracetamol) ?? true)
    }

    func testTemperatureConversionRoundTrips() {
        let celsius = 38.4
        XCTAssertEqual(TemperatureFormat.toCelsius(TemperatureFormat.fromCelsius(celsius)), celsius, accuracy: 0.0001)
    }
}
