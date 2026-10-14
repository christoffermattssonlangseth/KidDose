import UIKit

/// Builds a printable PDF of doses and temperature readings to show a doctor or nurse.
enum DoctorReport {
    static func makePDF(children: [Child], since start: Date, now: Date = .now) throws -> URL {
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

        let data = renderer.pdfData { context in
            for child in children {
                var page = PageWriter(context: context, pageRect: pageRect)
                page.beginPage()
                drawChild(child, from: start, to: now, on: &page)
            }
        }

        let stamp = now.formatted(.iso8601.year().month().day())
        let rawName = children.count == 1 ? children[0].name : "Family"
        let name = rawName.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KidDose-\(name)-\(stamp).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Content

    private static func drawChild(_ child: Child, from start: Date, to end: Date, on page: inout PageWriter) {
        let doses = child.doses
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp < $1.timestamp }
        let readings = child.temperatureReadings
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp < $1.timestamp }

        page.text("\(child.name) — medication and temperature summary", style: .title)
        page.text(
            "\(start.formatted(date: .abbreviated, time: .omitted)) to \(end.formatted(date: .abbreviated, time: .omitted)) · "
                + "Generated \(end.formatted(date: .abbreviated, time: .shortened))",
            style: .subtitle
        )
        page.space(14)

        // Summary
        page.text("Summary", style: .heading)
        for medication in Medication.allCases {
            let medDoses = doses.filter { $0.medication == medication.rawValue }
            guard !medDoses.isEmpty else { continue }
            let timestamps = child.doses.filter { $0.medication == medication.rawValue }.map(\.timestamp)
            let maxIn24h = medDoses
                .map { DoseRules.timestampsInWindow(timestamps, endingAt: $0.timestamp).count }
                .max() ?? 0
            var line = "\(medication.displayName): \(medDoses.count) dose\(medDoses.count == 1 ? "" : "s"), "
                + "most in any 24 h: \(maxIn24h)"
            if let limit = child.maxDailyDoses(for: medication) {
                line += " (limit set: \(limit))"
            }
            page.text(line, style: .body)
        }
        if doses.isEmpty {
            page.text("No doses in this period.", style: .body)
        }
        if let highest = readings.filter({ $0.celsius != nil }).max(by: { ($0.celsius ?? 0) < ($1.celsius ?? 0) }),
           let celsius = highest.celsius {
            page.text(
                "Highest temperature: \(TemperatureFormat.display(celsius)) on "
                    + highest.timestamp.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()),
                style: .body
            )
        }
        let feverCount = readings.filter(\.isFever).count
        if feverCount > 0 {
            page.text("Readings at or above \(TemperatureFormat.display(38.0)): \(feverCount)", style: .body)
        }
        page.space(14)

        // Timeline
        page.text("Timeline", style: .heading)
        page.row(["Date and time", "Event", "Details", "By"], style: .tableHeader)

        enum Item { case dose(DoseLog), reading(TemperatureLog) }
        let items: [(Date, Item)] = (doses.map { ($0.timestamp, Item.dose($0)) } + readings.map { ($0.timestamp, Item.reading($0)) })
            .sorted { $0.0 < $1.0 }

        if items.isEmpty {
            page.text("Nothing recorded in this period.", style: .body)
        }
        for (date, item) in items {
            let when = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            switch item {
            case .dose(let dose):
                var details: [String] = []
                if let amount = dose.amount { details.append(amount) }
                if dose.usedIntervalHours > 0 { details.append("every \(Int(dose.usedIntervalHours)) h") }
                page.row(
                    [when, dose.medicationEnum?.displayName ?? dose.medication.capitalized, details.joined(separator: ", "), dose.givenBy],
                    style: .tableRow
                )
            case .reading(let reading):
                var details: [String] = []
                if let celsius = reading.celsius { details.append(TemperatureFormat.display(celsius)) }
                if let symptoms = reading.symptoms { details.append(symptoms) }
                page.row(
                    [when, reading.celsius != nil ? "Temperature" : "Symptoms", details.joined(separator: " · "), reading.recordedBy],
                    style: reading.isFever ? .tableRowHighlighted : .tableRow
                )
            }
        }

        page.space(18)
        page.text("Recorded by parents in the KidDose app. This is a log, not medical advice.", style: .footnote)
    }
}

// MARK: - Page Writer

/// Minimal top-to-bottom text layout with automatic page breaks.
private struct PageWriter {
    enum Style {
        case title, subtitle, heading, body, footnote, tableHeader, tableRow, tableRowHighlighted
    }

    let context: UIGraphicsPDFRendererContext
    let pageRect: CGRect
    let margin: CGFloat = 40
    private(set) var y: CGFloat = 0

    /// Column widths as fractions of the content width.
    private let columns: [CGFloat] = [0.24, 0.17, 0.41, 0.18]

    init(context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        self.context = context
        self.pageRect = pageRect
    }

    private var contentWidth: CGFloat { pageRect.width - margin * 2 }

    mutating func beginPage() {
        context.beginPage()
        y = margin
    }

    mutating func space(_ amount: CGFloat) {
        y += amount
    }

    mutating func text(_ string: String, style: Style) {
        let attributed = NSAttributedString(string: string, attributes: attributes(for: style))
        let height = measure(attributed, width: contentWidth)
        ensureRoom(height)
        attributed.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height))
        y += height + 4
    }

    mutating func row(_ cells: [String], style: Style) {
        let attrs = attributes(for: style)
        let strings = cells.map { NSAttributedString(string: $0, attributes: attrs) }
        let widths = columns.map { $0 * contentWidth }
        let cellPadding: CGFloat = 4
        let height = zip(strings, widths)
            .map { measure($0, width: $1 - cellPadding * 2) }
            .max() ?? 12
        let rowHeight = height + cellPadding * 2
        ensureRoom(rowHeight)

        let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
        switch style {
        case .tableHeader:
            UIColor.systemGray5.setFill()
            UIBezierPath(rect: rowRect).fill()
        case .tableRowHighlighted:
            UIColor.systemRed.withAlphaComponent(0.08).setFill()
            UIBezierPath(rect: rowRect).fill()
        default:
            break
        }

        var x = margin
        for (string, width) in zip(strings, widths) {
            string.draw(in: CGRect(x: x + cellPadding, y: y + cellPadding, width: width - cellPadding * 2, height: height))
            x += width
        }

        UIColor.systemGray4.setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y + rowHeight))
        line.addLine(to: CGPoint(x: margin + contentWidth, y: y + rowHeight))
        line.lineWidth = 0.5
        line.stroke()

        y += rowHeight
    }

    private mutating func ensureRoom(_ height: CGFloat) {
        if y + height > pageRect.height - margin {
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

    private func attributes(for style: Style) -> [NSAttributedString.Key: Any] {
        let font: UIFont
        var color = UIColor.black
        switch style {
        case .title:
            font = .systemFont(ofSize: 20, weight: .bold)
        case .subtitle:
            font = .systemFont(ofSize: 11)
            color = .darkGray
        case .heading:
            font = .systemFont(ofSize: 14, weight: .semibold)
        case .body:
            font = .systemFont(ofSize: 11)
        case .footnote:
            font = .systemFont(ofSize: 9)
            color = .darkGray
        case .tableHeader:
            font = .systemFont(ofSize: 10, weight: .semibold)
        case .tableRow, .tableRowHighlighted:
            font = .systemFont(ofSize: 10)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }
}
