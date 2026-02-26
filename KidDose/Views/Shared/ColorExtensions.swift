import SwiftUI

extension Color {
    /// Initialise a Color from a hex string like "#FF5733" or "FF5733".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert a SwiftUI Color to a hex string. Falls back to gray on error.
    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    // MARK: - Preset child colors

    static let presetChildColors: [Color] = [
        Color(hex: "#FF6B6B"), // coral-red
        Color(hex: "#4ECDC4"), // teal
        Color(hex: "#45B7D1"), // sky blue
        Color(hex: "#96CEB4"), // sage green
        Color(hex: "#FFEAA7"), // pale yellow
        Color(hex: "#DDA0DD")  // plum
    ]
}

enum KidDoseLayout {
    static let cardCornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 10
    static let compactVerticalPadding: CGFloat = 7
    static let compactHorizontalPadding: CGFloat = 10
}

private struct KidDoseCardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

private struct KidDoseSubtleSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

extension View {
    func kidDoseCardSurface(cornerRadius: CGFloat = KidDoseLayout.cardCornerRadius) -> some View {
        modifier(KidDoseCardSurfaceModifier(cornerRadius: cornerRadius))
    }

    func kidDoseSubtleSurface(cornerRadius: CGFloat = KidDoseLayout.smallCornerRadius) -> some View {
        modifier(KidDoseSubtleSurfaceModifier(cornerRadius: cornerRadius))
    }
}
