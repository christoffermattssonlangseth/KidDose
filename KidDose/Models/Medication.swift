import SwiftUI

enum Medication: String, CaseIterable, Codable {
    case ibuprofen
    case paracetamol

    var intervalHours: Double {
        switch self {
        case .ibuprofen:    return 8.0
        case .paracetamol:  return 6.0
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
