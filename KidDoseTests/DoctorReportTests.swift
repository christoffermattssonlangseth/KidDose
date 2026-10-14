import XCTest
import PDFKit
@testable import KidDose

final class DoctorReportTests: XCTestCase {
    /// A three-day illness: alternating medications, a fever peak, and a long table.
    private func sampleReport(end: Date) -> DoctorReport.ChildReport {
        func hoursAgo(_ hours: Double) -> Date { end.addingTimeInterval(-hours * 3600) }
        var doses: [DoctorReport.Dose] = []
        for hours in stride(from: 70.0, to: 0, by: -8) {
            doses.append(.init(timestamp: hoursAgo(hours), medication: .paracetamol, intervalHours: 6,
                               amount: "7.5 ml", givenBy: hours.truncatingRemainder(dividingBy: 16) == 6 ? "Dad" : "Mom"))
        }
        for hours in stride(from: 66.0, to: 0, by: -9) {
            doses.append(.init(timestamp: hoursAgo(hours), medication: .ibuprofen, intervalHours: 8,
                               amount: "5 ml", givenBy: "Mom"))
        }
        let temps: [(Double, Double?, String?)] = [
            (71, 38.4, "Tired"), (64, 39.1, nil), (58, 39.4, "Earache"), (50, 38.6, nil),
            (44, 38.9, nil), (36, 38.2, "Not eating"), (28, 37.9, nil), (20, 37.6, nil),
            (12, 37.4, "Cough"), (4, 37.1, nil)
        ]
        let readings = temps.map {
            DoctorReport.Reading(timestamp: hoursAgo($0.0), celsius: $0.1, symptoms: $0.2, recordedBy: "Mom")
        }
        let sorted = doses.sorted { $0.timestamp < $1.timestamp }
        var allTimes: [Medication: [Date]] = [:]
        for medication in Medication.allCases {
            allTimes[medication] = sorted.filter { $0.medication == medication }.map(\.timestamp)
        }
        return DoctorReport.ChildReport(
            name: "Emma",
            colorHex: "#4ECDC4",
            doses: sorted,
            readings: readings,
            maxDailyDoses: [.paracetamol: 4, .ibuprofen: 3],
            allDoseTimes: allTimes
        )
    }

    func testRendersReadablePDF() throws {
        let end = Date(timeIntervalSince1970: 1_792_000_000)
        let data = DoctorReport.render([sampleReport(end: end)], from: end.addingTimeInterval(-7 * 86_400), to: end)

        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("Emma"))
        XCTAssertTrue(text.contains("Doses per day"))

        // Handy for eyeballing the layout: the path is printed in the test log.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KidDose-sample-report.pdf")
        try data.write(to: url)
        print("Sample report: \(url.path)")
    }
}
