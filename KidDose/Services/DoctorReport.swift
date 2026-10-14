import UIKit
import SwiftUI

/// Builds a printable PDF of doses and temperature readings to show a doctor or nurse.
///
/// Models are copied into plain values first (`ChildReport`), so rendering is a pure
/// function of data and can be previewed and tested without a SwiftData store.
enum DoctorReport {
    struct Dose {
        let timestamp: Date
        let medication: Medication
        let intervalHours: Double
        let amount: String?
        let givenBy: String
    }

    struct Reading {
        let timestamp: Date
        let celsius: Double?
        let symptoms: String?
        let recordedBy: String

        var isFever: Bool { (celsius ?? 0) >= 38.0 }
    }

    struct ChildReport {
        let name: String
        let colorHex: String
        /// Doses inside the report period, oldest first.
        let doses: [Dose]
        /// Readings inside the report period, oldest first.
        let readings: [Reading]
        let maxDailyDoses: [Medication: Int]
        /// Every dose time per medication, including before the period, for 24 h counts.
        let allDoseTimes: [Medication: [Date]]
    }

    static func makePDF(children: [Child], since start: Date, now: Date = .now) throws -> URL {
        let reports = children.map { report(for: $0, from: start, to: now) }
        let data = render(reports, from: start, to: now)

        let stamp = now.formatted(.iso8601.year().month().day())
        let rawName = children.count == 1 ? children[0].name : "Family"
        let name = rawName.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KidDose-\(name)-\(stamp).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func report(for child: Child, from start: Date, to end: Date) -> ChildReport {
        let inPeriod = { (date: Date) in date >= start && date <= end }
        let doses = child.doses
            .filter { inPeriod($0.timestamp) }
            .compactMap { dose -> Dose? in
                guard let medication = dose.medicationEnum else { return nil }
                return Dose(
                    timestamp: dose.timestamp,
                    medication: medication,
                    intervalHours: dose.usedIntervalHours > 0 ? dose.usedIntervalHours : medication.intervalHours,
                    amount: dose.amount,
                    givenBy: dose.givenBy
                )
            }
            .sorted { $0.timestamp < $1.timestamp }
        let readings = child.temperatureReadings
            .filter { inPeriod($0.timestamp) }
            .map { Reading(timestamp: $0.timestamp, celsius: $0.celsius, symptoms: $0.symptoms, recordedBy: $0.recordedBy) }
            .sorted { $0.timestamp < $1.timestamp }

        var limits: [Medication: Int] = [:]
        var allTimes: [Medication: [Date]] = [:]
        for medication in Medication.allCases {
            limits[medication] = child.maxDailyDoses(for: medication)
            allTimes[medication] = child.doses.filter { $0.medication == medication.rawValue }.map(\.timestamp)
        }
        return ChildReport(
            name: child.name,
            colorHex: child.colorHex,
            doses: doses,
            readings: readings,
            maxDailyDoses: limits,
            allDoseTimes: allTimes
        )
    }

    static func render(_ children: [ChildReport], from start: Date, to end: Date) -> Data {
        // A4 everywhere except US-style locales, which get US Letter.
        let usesLetter = Locale.current.measurementSystem == .us
        let pageRect = usesLetter
            ? CGRect(x: 0, y: 0, width: 612, height: 792)
            : CGRect(x: 0, y: 0, width: 595, height: 842)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "KidDose summary",
            kCGPDFContextCreator as String: "KidDose"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            let page = PageWriter(context: context, pageRect: pageRect)
            for child in children {
                page.beginPage()
                drawChild(child, from: start, to: end, on: page)
            }
        }
    }

    // MARK: - Content

    private static func drawChild(_ child: ChildReport, from start: Date, to end: Date, on page: PageWriter) {
        drawHeader(child, from: start, to: end, on: page)
        page.space(16)

        drawSummaryCards(child, on: page)
        page.space(22)

        drawTable(child, on: page)
    }

    private static func drawHeader(_ child: ChildReport, from start: Date, to end: Date, on page: PageWriter) {
        let tint = Palette.resolved(Color(hex: child.colorHex))
        let band = page.block(height: 76)
        Palette.fill(UIBezierPath(roundedRect: band, cornerRadius: 16), tint.withAlphaComponent(0.13))

        let avatar = CGRect(x: band.minX + 16, y: band.midY - 22, width: 44, height: 44)
        Palette.fill(UIBezierPath(ovalIn: avatar), tint)
        let initial = String(child.name.prefix(1)).uppercased()
        Text.draw(initial, font: Text.rounded(20, .bold), color: .white, centeredIn: avatar)

        let textX = avatar.maxX + 14
        Text.draw(child.name, font: Text.rounded(22, .bold), color: Palette.ink, at: CGPoint(x: textX, y: band.minY + 15))
        Text.draw("Medication and temperature summary", font: Text.rounded(11), color: Palette.secondary,
                  at: CGPoint(x: textX, y: band.minY + 45))

        let period = "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
        Text.draw(period, font: Text.rounded(11, .semibold), color: Palette.ink,
                  rightAlignedAt: CGPoint(x: band.maxX - 16, y: band.minY + 22))
        Text.draw("Generated \(end.formatted(date: .abbreviated, time: .shortened))", font: Text.rounded(9), color: Palette.muted,
                  rightAlignedAt: CGPoint(x: band.maxX - 16, y: band.minY + 40))
    }

    private static func drawSummaryCards(_ child: ChildReport, on page: PageWriter) {
        let medications = Medication.allCases.filter { med in child.doses.contains { $0.medication == med } }
        let temperatures = child.readings.compactMap(\.celsius)
        let cardCount = medications.count + (child.readings.isEmpty ? 0 : 1)

        guard cardCount > 0 else {
            page.text("Nothing recorded in this period.", font: Text.rounded(11), color: Palette.secondary)
            return
        }

        let row = page.block(height: 78)
        let gap: CGFloat = 10
        let width = (row.width - gap * CGFloat(cardCount - 1)) / CGFloat(cardCount)
        var x = row.minX

        func card(accent: UIColor) -> CGRect {
            let rect = CGRect(x: x, y: row.minY, width: width, height: row.height)
            Palette.fill(UIBezierPath(roundedRect: rect, cornerRadius: 12), Palette.surface)
            let bar = CGRect(x: rect.minX + 6, y: rect.minY + 10, width: 3.5, height: rect.height - 20)
            Palette.fill(UIBezierPath(roundedRect: bar, cornerRadius: 1.75), accent)
            x += width + gap
            return rect.insetBy(dx: 18, dy: 10).offsetBy(dx: 2, dy: 0)
        }

        for medication in medications {
            let doses = child.doses.filter { $0.medication == medication }
            let times = child.allDoseTimes[medication] ?? []
            let most = doses.map { DoseRules.timestampsInWindow(times, endingAt: $0.timestamp).count }.max() ?? 0
            let inner = card(accent: Palette.color(for: medication))

            Text.draw(medication.displayName, font: Text.rounded(10.5, .semibold), color: Palette.ink, at: inner.origin)
            let count = Text.attributed("\(doses.count)", font: Text.rounded(22, .bold), color: Palette.ink)
            count.draw(at: CGPoint(x: inner.minX, y: inner.minY + 14))
            Text.draw(doses.count == 1 ? "dose" : "doses", font: Text.rounded(10), color: Palette.secondary,
                      at: CGPoint(x: inner.minX + count.size().width + 4, y: inner.minY + 25))
            var detail = "Most in any 24 h: \(most)"
            if let limit = child.maxDailyDoses[medication] { detail += " · limit \(limit)" }
            Text.draw(detail, font: Text.rounded(8.5), color: Palette.secondary, at: CGPoint(x: inner.minX, y: inner.maxY - 11))
        }

        if !child.readings.isEmpty {
            let inner = card(accent: Palette.neutralLine)
            Text.draw("Temperature", font: Text.rounded(10.5, .semibold), color: Palette.ink, at: inner.origin)
            if let highest = temperatures.max() {
                Text.draw(TemperatureFormat.display(highest), font: Text.rounded(22, .bold), color: Palette.ink,
                          at: CGPoint(x: inner.minX, y: inner.minY + 14))
                Text.draw("highest", font: Text.rounded(10), color: Palette.secondary,
                          at: CGPoint(x: inner.minX + Text.attributed(TemperatureFormat.display(highest), font: Text.rounded(22, .bold), color: Palette.ink).size().width + 4,
                                      y: inner.minY + 25))
            } else {
                Text.draw("Symptoms only", font: Text.rounded(14, .semibold), color: Palette.ink,
                          at: CGPoint(x: inner.minX, y: inner.minY + 20))
            }
            let fevers = child.readings.filter(\.isFever).count
            Text.draw("\(child.readings.count) entries · \(fevers) at or above \(TemperatureFormat.display(38.0))",
                      font: Text.rounded(8.5), color: Palette.secondary, at: CGPoint(x: inner.minX, y: inner.maxY - 11))
        }
    }

    private static func drawTable(_ child: ChildReport, on page: PageWriter) {
        enum Item { case dose(Dose), reading(Reading) }
        let items: [(Date, Item)] = (child.doses.map { ($0.timestamp, Item.dose($0)) }
            + child.readings.map { ($0.timestamp, Item.reading($0)) })
            .sorted { $0.0 < $1.0 }
        guard !items.isEmpty else { return }

        page.heading("All entries", caption: nil)
        page.beginTable(["Date and time", "Event", "Details", "By"])
        defer { page.endTable() }

        for (date, item) in items {
            let when = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            switch item {
            case .dose(let dose):
                var details: [String] = []
                if let amount = dose.amount { details.append(amount) }
                details.append("every \(Int(dose.intervalHours)) h")
                page.tableRow(
                    [when, dose.medication.displayName, details.joined(separator: ", "), dose.givenBy],
                    dot: Palette.color(for: dose.medication),
                    highlighted: false
                )
            case .reading(let reading):
                var details: [String] = []
                if let celsius = reading.celsius {
                    details.append(TemperatureFormat.display(celsius) + (reading.isFever ? " (fever)" : ""))
                }
                if let symptoms = reading.symptoms { details.append(symptoms) }
                page.tableRow(
                    [when, reading.celsius != nil ? "Temperature" : "Symptoms", details.joined(separator: " · "), reading.recordedBy],
                    dot: Palette.neutralLine,
                    highlighted: reading.isFever
                )
            }
        }
    }
}

// MARK: - Palette and text

/// Fixed light colors: a PDF is printed on white whatever the phone's appearance.
private enum Palette {
    static let ink = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let secondary = UIColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 1)
    static let muted = UIColor(red: 0.54, green: 0.54, blue: 0.56, alpha: 1)
    static let grid = UIColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
    static let neutralLine = UIColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 1)
    static let surface = UIColor(red: 0.965, green: 0.965, blue: 0.97, alpha: 1)
    static let fever = UIColor(red: 0.84, green: 0.0, blue: 0.08, alpha: 1)

    static func resolved(_ color: Color) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }

    static func color(for medication: Medication) -> UIColor { resolved(medication.color) }

    static func fill(_ path: UIBezierPath, _ color: UIColor) {
        color.setFill()
        path.fill()
    }

    static func hLine(y: CGFloat, from x0: CGFloat, to x1: CGFloat, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x0, y: y))
        path.addLine(to: CGPoint(x: x1, y: y))
        path.lineWidth = 0.5
        color.setStroke()
        path.stroke()
    }

    /// A dot with a white ring so overlapping marks stay separate.
    static func marker(at point: CGPoint, radius: CGFloat, color: UIColor, ring: Bool = true) {
        if ring {
            fill(UIBezierPath(ovalIn: CGRect(x: point.x - radius - 1.5, y: point.y - radius - 1.5,
                                             width: (radius + 1.5) * 2, height: (radius + 1.5) * 2)), .white)
        }
        fill(UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), color)
    }
}

private enum Text {
    /// The app's rounded SF typography.
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func attributed(_ string: String, font: UIFont, color: UIColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
    }

    static func draw(_ string: String, font: UIFont, color: UIColor, at point: CGPoint) {
        attributed(string, font: font, color: color).draw(at: point)
    }

    static func draw(_ string: String, font: UIFont, color: UIColor, rightAlignedAt point: CGPoint) {
        let text = attributed(string, font: font, color: color)
        text.draw(at: CGPoint(x: point.x - text.size().width, y: point.y))
    }

    static func draw(_ string: String, font: UIFont, color: UIColor, centeredAt point: CGPoint) {
        let text = attributed(string, font: font, color: color)
        let size = text.size()
        text.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }

    static func draw(_ string: String, font: UIFont, color: UIColor, centeredIn rect: CGRect) {
        draw(string, font: font, color: color, centeredAt: CGPoint(x: rect.midX, y: rect.midY))
    }
}

// MARK: - Page Writer

/// Top-to-bottom layout with automatic page breaks and a footer on every page.
private final class PageWriter {
    let context: UIGraphicsPDFRendererContext
    let pageRect: CGRect
    let margin: CGFloat = 40
    let footerHeight: CGFloat = 24
    private(set) var y: CGFloat = 0
    private var pageNumber = 0
    /// Column titles repeated at the top of each page while a table is being drawn.
    private var tableColumns: [String]?

    /// Column widths as fractions of the content width.
    private let columns: [CGFloat] = [0.23, 0.18, 0.41, 0.18]

    init(context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        self.context = context
        self.pageRect = pageRect
    }

    var contentWidth: CGFloat { pageRect.width - margin * 2 }
    private var bottom: CGFloat { pageRect.height - margin - footerHeight }

    func beginPage() {
        context.beginPage()
        pageNumber += 1
        y = margin
        drawFooter()
        if let tableColumns {
            drawTableHeader(tableColumns)
        }
    }

    func space(_ amount: CGFloat) {
        y += amount
    }

    /// Reserves a rectangle of the given height, starting a new page if it does not fit.
    func block(height: CGFloat) -> CGRect {
        ensureRoom(height)
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: height)
        y += height
        return rect
    }

    func text(_ string: String, font: UIFont, color: UIColor) {
        let attributed = Text.attributed(string, font: font, color: color)
        let height = measure(attributed, width: contentWidth)
        ensureRoom(height)
        attributed.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height))
        y += height + 4
    }

    /// Section heading kept on the same page as at least the start of its content.
    func heading(_ title: String, caption: String?) {
        ensureRoom(80)
        text(title, font: Text.rounded(14, .bold), color: Palette.ink)
        if let caption {
            text(caption, font: Text.rounded(8.5), color: Palette.secondary)
        }
        space(4)
    }

    /// Starts a table; its header repeats on following pages until `endTable()`.
    func beginTable(_ cells: [String]) {
        ensureRoom(20 + 30)
        drawTableHeader(cells)
        tableColumns = cells
    }

    func endTable() {
        tableColumns = nil
    }

    private func drawTableHeader(_ cells: [String]) {
        let font = Text.rounded(8.5, .semibold)
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 20)
        y += 20
        Palette.fill(UIBezierPath(roundedRect: rect, cornerRadius: 6), Palette.surface)
        var x = margin
        for (cell, fraction) in zip(cells, columns) {
            Text.draw(cell, font: font, color: Palette.secondary, at: CGPoint(x: x + 8, y: rect.minY + 5))
            x += fraction * contentWidth
        }
    }

    func tableRow(_ cells: [String], dot: UIColor, highlighted: Bool) {
        let font = Text.rounded(9)
        let padding: CGFloat = 5
        let widths = columns.map { $0 * contentWidth }
        let strings = cells.map { Text.attributed($0, font: font, color: Palette.ink) }
        let textInsets: [CGFloat] = [8, 20, 8, 8]   // the Event column leaves room for its dot
        let height = zip(zip(strings, widths), textInsets)
            .map { measure($0.0, width: $0.1 - $1 - padding) }
            .max() ?? 12
        let rowHeight = height + padding * 2
        ensureRoom(rowHeight)

        let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
        if highlighted {
            Palette.fill(UIBezierPath(roundedRect: rowRect, cornerRadius: 6), Palette.fever.withAlphaComponent(0.07))
        }

        var x = margin
        for (index, (string, width)) in zip(strings, widths).enumerated() {
            let inset = textInsets[index]
            if index == 1 {
                Palette.marker(at: CGPoint(x: x + 12, y: y + padding + 6), radius: 3, color: dot, ring: false)
            }
            string.draw(in: CGRect(x: x + inset, y: y + padding, width: width - inset - padding, height: height))
            x += width
        }
        Palette.hLine(y: y + rowHeight, from: margin, to: margin + contentWidth, color: Palette.grid)
        y += rowHeight
    }

    private func drawFooter() {
        let lineY = pageRect.height - margin - 12
        Palette.hLine(y: lineY, from: margin, to: margin + contentWidth, color: Palette.grid)
        let left = Text.attributed("KidDose", font: Text.rounded(8, .bold), color: Palette.secondary)
        left.draw(at: CGPoint(x: margin, y: lineY + 4))
        Text.draw("  ·  Recorded by parents. This is a log, not medical advice.", font: Text.rounded(8), color: Palette.muted,
                  at: CGPoint(x: margin + left.size().width, y: lineY + 4))
        Text.draw("Page \(pageNumber)", font: Text.rounded(8), color: Palette.muted,
                  rightAlignedAt: CGPoint(x: margin + contentWidth, y: lineY + 4))
    }

    private func ensureRoom(_ height: CGFloat) {
        if y + height > bottom {
            beginPage()
        }
    }

    private func measure(_ string: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(string.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
    }
}
