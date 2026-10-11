import SwiftUI

/// Production artwork is independent of the optional animation design gallery.
struct RippleOpeningArtwork: View {
    @Environment(\.appTheme) private var theme
    let time: Double
    let size: CGFloat

    private var progress: Double {
        let value = min(max(time / 1.65, 0), 1)
        return value * value * (3 - 2 * value)
    }

    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                let phase = min(max((time - Double(index) * 0.12) / 1.4, 0), 1)
                let eased = phase * phase * (3 - 2 * phase)
                let diameter = size * (0.84 - Double(index) * 0.10 - eased * 0.25)
                Circle()
                    .stroke(theme.accentPrimary.opacity(0.10 + Double(index) * 0.08),
                            lineWidth: index == 3 ? size * 0.014 : 1)
                    .frame(width: diameter, height: diameter)
                    .offset(y: (1 - eased) * size * Double(index - 2) * 0.035)
            }
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.10, weight: .light))
                .foregroundStyle(theme.accentPrimary)
                .scaleEffect(0.4 + progress * 0.6)
                .opacity(progress)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
