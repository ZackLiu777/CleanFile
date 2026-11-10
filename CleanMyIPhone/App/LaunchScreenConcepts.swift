#if DEBUG
import SwiftUI

/// Independent launch screen studies for the Xcode canvas.
private struct LaunchScreenConcept: View {
    enum Style {
        case editorial, blueprint, orbit

        func palette(dark: Bool) -> Palette {
            switch (self, dark) {
            case (.editorial, false): Palette(0xF5E9D7, 0x2D211C, 0xA63B26)
            case (.editorial, true): Palette(0x271A15, 0xF7E6CF, 0xFF946E)
            case (.blueprint, false): Palette(0xEDF4FF, 0x102853, 0x214EBA)
            case (.blueprint, true): Palette(0x09162D, 0xE1EDFF, 0x86AFFF)
            case (.orbit, false): Palette(0xF4EDFF, 0x251843, 0x6436AD)
            case (.orbit, true): Palette(0x161027, 0xF4EBFF, 0xCFACFF)
            }
        }
    }

    struct Palette {
        let paper: Color
        let ink: Color
        let accent: Color

        init(_ paper: UInt32, _ ink: UInt32, _ accent: UInt32) {
            self.paper = Self.color(paper)
            self.ink = Self.color(ink)
            self.accent = Self.color(accent)
        }

        private static func color(_ hex: UInt32) -> Color {
            Color(
                red: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255
            )
        }
    }

    let style: Style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize = 58

    var body: some View {
        let palette = style.palette(dark: colorScheme == .dark)

        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: style == .editorial ? .leading : .center, spacing: 24) {
                    Spacer(minLength: 24)
                    if style == .editorial { identity }
                    artwork(palette)
                        .frame(height: min(geometry.size.width * 0.60, 260))
                        .accessibilityHidden(true)
                    if style != .editorial { identity }
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(palette.ink)
        .background {
            palette.paper.ignoresSafeArea()
            if style == .orbit && !reduceTransparency {
                RadialGradient(colors: [palette.accent.opacity(0.20), .clear],
                               center: .center, startRadius: 8, endRadius: 340)
                    .ignoresSafeArea()
            }
        }
    }

    private var identity: some View {
        VStack(alignment: style == .editorial ? .leading : .center, spacing: 8) {
            Text(verbatim: "Filevra")
                .font(.system(size: wordmarkSize, weight: style == .orbit ? .medium : .bold,
                              design: wordmarkDesign))
                .accessibilityAddTraits(.isHeader)
            subtitle
                .font(style == .blueprint ? .callout.monospaced() : .callout)
        }
        .multilineTextAlignment(style == .editorial ? .leading : .center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var wordmarkDesign: Font.Design {
        switch style {
        case .editorial: .serif
        case .blueprint: .monospaced
        case .orbit: .rounded
        }
    }

    private var subtitle: Text {
        switch style {
        case .editorial: Text("A little more room.")
        case .blueprint: Text("Clean up. Make space.")
        case .orbit: Text("Space for what matters.")
        }
    }

    private func artwork(_ palette: Palette) -> some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 240
            var drawing = context
            drawing.translateBy(x: size.width / 2, y: size.height / 2)
            drawing.scaleBy(x: unit, y: unit)

            switch style {
            case .editorial:
                for (offset, angle) in [(-40.0, -0.24), (0, 0), (40, 0.24)] {
                    var sheet = drawing
                    sheet.translateBy(x: offset, y: abs(offset) / 3)
                    sheet.rotate(by: .radians(angle))
                    let page = Path(roundedRect: CGRect(x: -43, y: -74, width: 86, height: 148),
                                    cornerRadius: 5)
                    sheet.fill(page, with: .color(palette.accent))
                    sheet.stroke(page, with: .color(palette.paper), lineWidth: 2)
                    for y in [10.0, 24, 38] {
                        sheet.fill(Path(CGRect(x: -22, y: y, width: 44, height: 2)),
                                   with: .color(palette.paper))
                    }
                }
            case .blueprint:
                var grid = Path()
                for step in -5...5 {
                    let offset = CGFloat(step) * 20
                    grid.move(to: CGPoint(x: offset, y: -100))
                    grid.addLine(to: CGPoint(x: offset, y: 100))
                    grid.move(to: CGPoint(x: -100, y: offset))
                    grid.addLine(to: CGPoint(x: 100, y: offset))
                }
                drawing.stroke(grid, with: .color(palette.accent.opacity(0.25)))
                let blocks = [CGRect(x: -60, y: -60, width: 116, height: 36),
                              CGRect(x: -60, y: -16, width: 76, height: 36),
                              CGRect(x: -60, y: 28, width: 36, height: 36)]
                for block in blocks {
                    drawing.fill(Path(roundedRect: block, cornerRadius: 4), with: .color(palette.accent))
                }
                let emptySlot = Path(roundedRect: CGRect(x: 24, y: -16, width: 32, height: 36),
                                     cornerRadius: 4)
                drawing.stroke(emptySlot, with: .color(palette.accent),
                               style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            case .orbit:
                for angle in [-0.62, 0.62] {
                    var orbit = drawing
                    orbit.rotate(by: .radians(angle))
                    orbit.stroke(Path(ellipseIn: CGRect(x: -108, y: -43, width: 216, height: 86)),
                                 with: .color(palette.accent.opacity(0.65)), lineWidth: 1.5)
                    orbit.fill(Path(ellipseIn: CGRect(x: 99, y: -5, width: 10, height: 10)),
                               with: .color(palette.accent))
                }
                let core = Path(ellipseIn: CGRect(x: -38, y: -38, width: 76, height: 76))
                drawing.fill(core, with: .linearGradient(
                    Gradient(colors: [palette.accent, palette.ink]),
                    startPoint: CGPoint(x: -32, y: -32),
                    endPoint: CGPoint(x: 38, y: 38)
                ))
            }
        }
    }
}

#Preview("Editorial · Light") {
    LaunchScreenConcept(style: .editorial).preferredColorScheme(.light)
}

#Preview("Editorial · Dark") {
    LaunchScreenConcept(style: .editorial).preferredColorScheme(.dark)
}

#Preview("Blueprint · Light") {
    LaunchScreenConcept(style: .blueprint).preferredColorScheme(.light)
}

#Preview("Blueprint · Dark") {
    LaunchScreenConcept(style: .blueprint).preferredColorScheme(.dark)
}

#Preview("Orbit · Light") {
    LaunchScreenConcept(style: .orbit).preferredColorScheme(.light)
}

#Preview("Orbit · Dark") {
    LaunchScreenConcept(style: .orbit).preferredColorScheme(.dark)
}
#endif
