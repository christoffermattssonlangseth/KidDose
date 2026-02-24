import SwiftUI

enum Medication: String, CaseIterable, Codable {
    case ibuprofen
    case paracetamol

    /// Default interval used when no override is specified.
    var intervalHours: Double {
        switch self {
        case .ibuprofen:    return 8.0
        case .paracetamol:  return 6.0
        }
    }

    /// All selectable intervals for this medication.
    /// Ibuprofen can be given every 6 h or every 8 h; paracetamol is fixed at 6 h.
    var availableIntervals: [Double] {
        switch self {
        case .ibuprofen:    return [6.0, 8.0]
        case .paracetamol:  return [6.0]
        }
    }

    var displayName: String {
        switch self {
        case .ibuprofen:    return "Ibuprofen"
        case .paracetamol:  return "Paracetamol"
        }
    }

    var color: Color {
        switch self {
        case .ibuprofen:    return .orange
        case .paracetamol:  return .blue
        }
    }

    var iconName: String {
        switch self {
        case .ibuprofen:    return "flame.fill"
        case .paracetamol:  return "cross.fill"
        }
    }

    var notificationIdentifier: String {
        rawValue
    }
}
