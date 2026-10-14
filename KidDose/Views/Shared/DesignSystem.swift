import SwiftUI
import UIKit

// MARK: - Tokens
//
// Central place for spacing, corner radius, and typography constants. Prefer
// these over hard-coded values so the whole app moves together when we tune
// the look. `KidDoseLayout` stays as-is for now; new code reaches for `Tokens`.

enum Tokens {
    enum Space {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let s:   CGFloat = 8
        static let m:   CGFloat = 12
        static let l:   CGFloat = 16
        static let xl:  CGFloat = 24
    }

    enum Radius {
        static let chip:  CGFloat = 999
        static let small: CGFloat = 10
        static let card:  CGFloat = 14
        static let hero:  CGFloat = 16
    }

    enum Stroke {
        static let hairline:   CGFloat = 1
        static let emphasized: CGFloat = 1.5
    }
}

// MARK: - Status Tone

/// Semantic colour role for a dose state. Views shouldn't reach for `.red` /
/// `.green` directly — they pick a tone and the design system decides the hue.
enum StatusTone {
    case ready
    case overdue
    case skipped
    case neutral
    case accent(Color)

    var color: Color {
        switch self {
        case .ready:          return .green
        case .overdue:        return .red
        case .skipped:        return .orange
        case .neutral:        return .secondary
        case .accent(let c):  return c
        }
    }

    var tintedBackground: Color { color.opacity(0.14) }
}

// MARK: - Status Badge

/// Small pill used for "Ready", "Overdue", "Dose Skipped" and the like.
/// Consolidates three near-identical Labels in MedicationCard into one view.
struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tone: StatusTone
    var bounceOn: AnyHashable? = nil
    var accessibilityDescription: String? = nil

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .modifier(OptionalBounce(value: bounceOn))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.color)
        .accessibilityLabel(accessibilityDescription ?? text)
    }
}

private struct OptionalBounce: ViewModifier {
    let value: AnyHashable?

    func body(content: Content) -> some View {
        if let value {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}

// MARK: - Pill Chip

enum PillChipStyle {
    /// Text stays `.primary`; tone only tints the background. Hairline border.
    case neutralText
    /// Text adopts the tone colour; no border. Good for status labels.
    case tintedText
}

/// Tiny rounded pill for status labels inside rows.
struct PillChip: View {
    let text: String
    var systemImage: String? = nil
    let tone: StatusTone
    var style: PillChipStyle = .neutralText

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(style == .tintedText ? tone.color : .primary)
        .padding(.horizontal, Tokens.Space.s + 2)
        .padding(.vertical, 4)
        .background(tone.tintedBackground, in: Capsule())
        .overlay {
            if style == .neutralText {
                Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: Tokens.Stroke.hairline)
            }
        }
    }
}

// MARK: - Hero Surface

/// Chrome for "hero" cards — big background tint keyed off a child or
/// medication colour, soft shadow, subtle border. Use for one-per-screen
/// attention-grabbing surfaces, not every card.
struct HeroSurface: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(Tokens.Space.l)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.hero, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.22), tint.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.hero, style: .continuous))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.hero, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: Tokens.Stroke.hairline)
            }
            .shadow(color: tint.opacity(0.12), radius: 10, y: 4)
    }
}

extension View {
    func heroSurface(tint: Color) -> some View {
        modifier(HeroSurface(tint: tint))
    }
}

// MARK: - Selectable Chip

/// Pill-shaped toggle button used for filters and mode switches. Replaces
/// `FilterChip` and `HistoryModeToggleChip` — same chrome, two behaviours:
///   • Pass `systemImage` to mirror a systemImage when unselected (filter mode)
///   • Omit it to show a label-only chip with a checkmark only when selected
struct SelectableChip: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    let tint: Color
    var unselectedLabelWeight: Font.Weight = .semibold
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.xs + 2) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").imageScale(.small)
                } else if let systemImage {
                    Image(systemName: systemImage).imageScale(.small)
                }
                Text(label)
                    .font(.subheadline.weight(isSelected ? .semibold : unselectedLabelWeight))
            }
            .padding(.horizontal, Tokens.Space.m - 2)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background(
                isSelected ? tint.opacity(0.18) : Color(UIColor.tertiarySystemBackground),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? tint : .primary.opacity(0.08),
                    lineWidth: Tokens.Stroke.emphasized
                )
            }
        }
        .buttonStyle(.plain)
    }
}
