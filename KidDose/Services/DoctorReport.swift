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

        if !child.doses.isEmpty || child.readings.contains(where: { $0.celsius != nil }) {
            page.heading("Timeline", caption: "Each dot is a dose; the pale bar is its waiting period. Shaded columns are night, 22–06.")
            ReportCharts.timeline(child, end: end, on: page)
            page.space(22)
        }

        if ReportCharts.hasDailyBars(child) {
            page.heading("Doses per day", caption: "Calendar days. The daily limit counts any rolling 24 hours; see the summary above.")
            ReportCharts.dosesPerDay(child, end: end, on: page)
            page.space(22)
        }

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

// MARK: - Charts

private enum ReportCharts {
    static let gutter: CGFloat = 88
    static let calendar = Calendar.current

    /// Medication lanes plus a temperature panel above them, sharing one time axis.
    static func timeline(_ child: DoctorReport.ChildReport, end: Date, on page: PageWriter) {
        let temps = child.readings.filter { $0.celsius != nil }
        let medications = Medication.allCases.filter { med in child.doses.contains { $0.medication == med } }

        let firstEvent = (child.doses.map(\.timestamp) + temps.map(\.timestamp)).min() ?? end
        var domainStart = calendar.startOfDay(for: firstEvent)
        if end.timeIntervalSince(domainStart) < 12 * 3600 { domainStart = end.addingTimeInterval(-12 * 3600) }
        let domain = domainStart...end
        let days = end.timeIntervalSince(domainStart) / 86_400

        let tempHeight: CGFloat = temps.isEmpty ? 0 : 118
        let laneHeight: CGFloat = 26
        let axisHeight: CGFloat = 16
        let panelGap: CGFloat = temps.isEmpty ? 0 : 10
        let total = tempHeight + panelGap + laneHeight * CGFloat(medications.count) + axisHeight
        let rect = page.block(height: total)

        let plot = CGRect(x: rect.minX + gutter, y: rect.minY, width: rect.width - gutter - 6, height: total - axisHeight)
        func x(_ date: Date) -> CGFloat {
            let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
            return plot.minX + CGFloat(date.timeIntervalSince(domain.lowerBound) / span) * plot.width
        }

        // Night shading and day lines across every panel.
        page.clipped(to: plot) {
            var day = calendar.startOfDay(for: domain.lowerBound).addingTimeInterval(-86_400)
            while day < end {
                let nightStart = day.addingTimeInterval(22 * 3600)
                let nightEnd = day.addingTimeInterval(30 * 3600)
                Palette.fill(UIBezierPath(rect: CGRect(x: x(nightStart), y: plot.minY, width: x(nightEnd) - x(nightStart), height: plot.height)),
                             Palette.night)
                day = day.addingTimeInterval(86_400)
            }
        }
        var tick = calendar.startOfDay(for: domain.lowerBound)
        let tickStep: TimeInterval = days <= 3 ? 6 * 3600 : 86_400
        while tick <= end {
            if tick >= domain.lowerBound {
                let isMidnight = calendar.startOfDay(for: tick) == tick
                Palette.vLine(x: x(tick), from: plot.minY, to: plot.maxY + 3, color: isMidnight ? Palette.grid : Palette.grid.withAlphaComponent(0.5))
                let label = isMidnight
                    ? tick.formatted(.dateTime.weekday(.abbreviated).day())
                    : tick.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
                Text.draw(label, font: Text.rounded(7.5, isMidnight ? .semibold : .regular), color: Palette.muted,
                          at: CGPoint(x: x(tick) + 2.5, y: plot.maxY + 3))
            }
            tick = tick.addingTimeInterval(tickStep)
        }

        // Temperature panel.
        if !temps.isEmpty {
            let panel = CGRect(x: plot.minX, y: plot.minY, width: plot.width, height: tempHeight)
            let values = temps.compactMap(\.celsius).map(TemperatureFormat.fromCelsius)
            let fever = TemperatureFormat.fromCelsius(38.0)
            let step: Double = TemperatureFormat.usesFahrenheit ? 2 : 1
            let low = (min(values.min()!, TemperatureFormat.fromCelsius(36.5)) / step).rounded(.down) * step
            let high = (max(values.max()!, TemperatureFormat.fromCelsius(39.5)) / step).rounded(.up) * step
            func y(_ value: Double) -> CGFloat {
                panel.maxY - 6 - CGFloat((value - low) / (high - low)) * (panel.height - 12)
            }

            Text.draw("Temperature", font: Text.rounded(9, .semibold), color: Palette.ink, at: CGPoint(x: rect.minX, y: panel.minY))
            var g = low
            while g <= high {
                Palette.hLine(y: y(g), from: panel.minX, to: panel.maxX, color: Palette.grid)
                Text.draw("\(Int(g))°", font: Text.rounded(7.5), color: Palette.muted,
                          rightAlignedAt: CGPoint(x: panel.minX - 5, y: y(g) - 4.5))
                g += step
            }

            let feverLine = UIBezierPath()
            feverLine.move(to: CGPoint(x: panel.minX, y: y(fever)))
            feverLine.addLine(to: CGPoint(x: panel.maxX, y: y(fever)))
            feverLine.lineWidth = 1
            feverLine.setLineDash([3, 3], count: 2, phase: 0)
            Palette.fever.withAlphaComponent(0.7).setStroke()
            feverLine.stroke()
            Text.draw("Fever \(TemperatureFormat.display(38.0))", font: Text.rounded(7.5, .semibold), color: Palette.secondary,
                      rightAlignedAt: CGPoint(x: panel.maxX - 2, y: y(fever) - 11))

            let points = temps.map { CGPoint(x: x($0.timestamp), y: y(TemperatureFormat.fromCelsius($0.celsius!))) }
            if points.count > 1 {
                let line = UIBezierPath()
                line.move(to: points[0])
                points.dropFirst().forEach { line.addLine(to: $0) }
                line.lineWidth = 2
                line.lineJoinStyle = .round
                line.lineCapStyle = .round
                Palette.tempLine.setStroke()
                line.stroke()
            }
            for (reading, point) in zip(temps, points) {
                Palette.marker(at: point, radius: 3.5, color: reading.isFever ? Palette.fever : Palette.tempLine)
            }
            // Label only the peak, to keep the panel quiet.
            if let peakIndex = temps.indices.max(by: { temps[$0].celsius! < temps[$1].celsius! }) {
                let point = points[peakIndex]
                Text.draw(TemperatureFormat.display(temps[peakIndex].celsius!), font: Text.rounded(8, .semibold), color: Palette.ink,
                          centeredAt: CGPoint(x: min(max(point.x, panel.minX + 20), panel.maxX - 20), y: point.y - 11))
            }
        }

        // Medication lanes.
        var laneY = plot.minY + tempHeight + panelGap
        for medication in medications {
            let lane = CGRect(x: plot.minX, y: laneY, width: plot.width, height: laneHeight)
            let color = Palette.color(for: medication)
            Palette.marker(at: CGPoint(x: rect.minX + 4, y: lane.midY), radius: 3.5, color: color, ring: false)
            Text.draw(medication.displayName, font: Text.rounded(9, .semibold), color: Palette.ink,
                      at: CGPoint(x: rect.minX + 12, y: lane.midY - 6))
            Palette.hLine(y: lane.midY, from: lane.minX, to: lane.maxX, color: Palette.grid)

            let doses = child.doses.filter { $0.medication == medication }
            page.clipped(to: lane) {
                for dose in doses {
                    let start = x(dose.timestamp)
                    let stop = x(dose.timestamp.addingTimeInterval(dose.intervalHours * 3600))
                    let bar = CGRect(x: start, y: lane.midY - 5, width: max(stop - start, 2), height: 10)
                    Palette.fill(UIBezierPath(roundedRect: bar, cornerRadius: 5), color.withAlphaComponent(0.22))
                }
            }
            for dose in doses {
                Palette.marker(at: CGPoint(x: x(dose.timestamp), y: lane.midY), radius: 4.5, color: color)
            }
            laneY += laneHeight
        }
    }

    static func hasDailyBars(_ child: DoctorReport.ChildReport) -> Bool {
        Set(child.doses.map { calendar.startOfDay(for: $0.timestamp) }).count >= 2
    }

    /// Grouped bars: one per medication per calendar day.
    static func dosesPerDay(_ child: DoctorReport.ChildReport, end: Date, on page: PageWriter) {
        let medications = Medication.allCases.filter { med in child.doses.contains { $0.medication == med } }
        guard let first = child.doses.map(\.timestamp).min() else { return }
        var days: [Date] = []
        var day = calendar.startOfDay(for: first)
        while day <= end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        let counts = days.map { day in
            medications.map { med in child.doses.filter { $0.medication == med && calendar.isDate($0.timestamp, inSameDayAs: day) }.count }
        }
        let maxCount = max(counts.flatMap { $0 }.max() ?? 1, 2)

        let rect = page.block(height: 112)
        let legendHeight: CGFloat = 14
        let plot = CGRect(x: rect.minX + gutter, y: rect.minY + legendHeight + 10, width: rect.width - gutter - 6,
                          height: rect.height - legendHeight - 10 - 16)

        // Legend (two series), right-aligned above the plot.
        var legendX = plot.maxX
        for medication in medications.reversed() {
            let label = Text.attributed(medication.displayName, font: Text.rounded(8.5), color: Palette.secondary)
            legendX -= label.size().width
            label.draw(at: CGPoint(x: legendX, y: rect.minY))
            legendX -= 10
            Palette.marker(at: CGPoint(x: legendX + 3.5, y: rect.minY + 5.5), radius: 3.5, color: Palette.color(for: medication), ring: false)
            legendX -= 12
        }

        func y(_ value: Int) -> CGFloat { plot.maxY - CGFloat(value) / CGFloat(maxCount) * plot.height }
        let gridStep = maxCount <= 6 ? 1 : 2
        for value in stride(from: 0, through: maxCount, by: gridStep) {
            Palette.hLine(y: y(value), from: plot.minX, to: plot.maxX, color: value == 0 ? Palette.neutralLine : Palette.grid)
            Text.draw("\(value)", font: Text.rounded(7.5), color: Palette.muted, rightAlignedAt: CGPoint(x: plot.minX - 5, y: y(value) - 4.5))
        }

        let slot = plot.width / CGFloat(days.count)
        let barWidth = min(14, slot * 0.3)
        let gap: CGFloat = 2
        let groupWidth = barWidth * CGFloat(medications.count) + gap * CGFloat(medications.count - 1)
        for (index, day) in days.enumerated() {
            let groupX = plot.minX + slot * CGFloat(index) + (slot - groupWidth) / 2
            for (m, medication) in medications.enumerated() {
                let count = counts[index][m]
                guard count > 0 else { continue }
                let bar = CGRect(x: groupX + CGFloat(m) * (barWidth + gap), y: y(count), width: barWidth, height: plot.maxY - y(count))
                Palette.fill(
                    UIBezierPath(roundedRect: bar, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 3, height: 3)),
                    Palette.color(for: medication)
                )
                Text.draw("\(count)", font: Text.rounded(7.5, .semibold), color: Palette.ink, centeredAt: CGPoint(x: bar.midX, y: bar.minY - 6))
            }
            Text.draw(day.formatted(.dateTime.weekday(.abbreviated).day()), font: Text.rounded(7.5), color: Palette.muted,
                      centeredAt: CGPoint(x: plot.minX + slot * (CGFloat(index) + 0.5), y: plot.maxY + 8))
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
    static let night = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    static let tempLine = UIColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)
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

    static func vLine(x: CGFloat, from y0: CGFloat, to y1: CGFloat, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: y0))
        path.addLine(to: CGPoint(x: x, y: y1))
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

    func clipped(to rect: CGRect, _ draw: () -> Void) {
        context.cgContext.saveGState()
        UIBezierPath(rect: rect).addClip()
        draw()
        context.cgContext.restoreGState()
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
