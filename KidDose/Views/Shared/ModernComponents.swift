import SwiftUI

// MARK: - Liquid Glass (iOS 26) with material fallback

extension View {
    /// Liquid Glass on iOS 26, a thin material with a hairline stroke on earlier versions.
    /// Meant for floating controls (switchers, chip bars), not for content cards.
    @ViewBuilder
    func kidDoseGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(kidDoseGlassStyle(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }

    /// Prominent capsule action button: Liquid Glass on iOS 26, bordered-prominent before.
    @ViewBuilder
    func kidDoseProminentButton(tint: Color) -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(tint)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(tint)
        }
    }

    /// Secondary capsule button: Liquid Glass on iOS 26, bordered before.
    @ViewBuilder
    func kidDoseSecondaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }

    /// Marks a view as the source of a zoom navigation transition (iOS 18+).
    @ViewBuilder
    func kidDoseZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Zooms a pushed screen out of its source view (iOS 18+); a normal push before.
    @ViewBuilder
    func kidDoseZoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// Cards ease back and fade a little as they scroll off screen.
    func kidDoseScrollDepth() -> some View {
        scrollTransition(.animated(.smooth)) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.55)
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                .blur(radius: phase.isIdentity ? 0 : 1.5)
        }
    }
}

@available(iOS 26.0, *)
private func kidDoseGlassStyle(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint {
        glass = glass.tint(tint)
    }
    if interactive {
        glass = glass.interactive()
    }
    return glass
}

// MARK: - Progress Ring

/// A circular progress ring with arbitrary content in the middle.
struct DoseProgressRing<Center: View>: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat
    let center: Center

    init(
        progress: Double,
        tint: Color,
        lineWidth: CGFloat = 6,
        @ViewBuilder center: () -> Center
    ) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
        self.center = center()
    }

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: clamped)
            center
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((clamped * 100).rounded())) percent of the interval has passed")
    }
}

// MARK: - Countdown formatting

enum KidDoseTime {
    /// "2:14:07", or "14:07" under an hour. Reads like a timer and rolls nicely with `.numericText`.
    static func timer(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded(.up)), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Fraction of a dosing interval that has elapsed at `now`.
    static func progress(start: Date?, end: Date, now: Date) -> Double {
        guard let start, end > start else { return now >= end ? 1 : 0 }
        return now.timeIntervalSince(start) / end.timeIntervalSince(start)
    }
}

// MARK: - Status Pill

/// Small tinted capsule used for Ready / Overdue / Skipped states.
struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color
    var pulses: Bool = false

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolEffect(.pulse, options: .repeating, isActive: pulses)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }
}
