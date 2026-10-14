import SwiftData
import Foundation

/// A temperature reading and/or symptom note for a child, shown alongside doses in History
/// and in the doctor summary.
@Model
final class TemperatureLog {
    var timestamp: Date = Date.now
    /// Stored in Celsius; shown in the user's preferred unit.
    var celsius: Double?
    var symptoms: String?
    var recordedBy: String = ""
    var cloudRecordName: String?

    var child: Child?

    init(
        timestamp: Date = .now,
        celsius: Double?,
        symptoms: String?,
        recordedBy: String,
        child: Child,
        cloudRecordName: String? = nil
    ) {
        self.timestamp = timestamp
        self.celsius = celsius
        let trimmed = symptoms?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symptoms = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.recordedBy = recordedBy
        self.child = child
        self.cloudRecordName = cloudRecordName
    }

    /// 38.0 °C and above is commonly treated as a fever in children.
    var isFever: Bool { (celsius ?? 0) >= 38.0 }
}

enum TemperatureFormat {
    /// Fahrenheit for the US measurement system, Celsius elsewhere.
    static var usesFahrenheit: Bool {
        Locale.current.measurementSystem == .us
    }

    static func display(_ celsius: Double) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: usesFahrenheit ? .fahrenheit : .celsius)
        return measurement.formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
        )
    }

    static func toCelsius(_ value: Double) -> Double {
        usesFahrenheit ? (value - 32) * 5 / 9 : value
    }

    static func fromCelsius(_ celsius: Double) -> Double {
        usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    static var unitSymbol: String { usesFahrenheit ? "°F" : "°C" }
}
