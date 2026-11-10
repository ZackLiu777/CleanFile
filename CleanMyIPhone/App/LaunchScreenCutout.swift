#if DEBUG
import SwiftUI

/// A poster-style launch study built from flat, overlapping cutouts.
private struct CutoutLaunchScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 68

    private var dark: Bool { colorScheme == .dark }
    private var paper: Color {
        dark ? Color(red: 0.055, green: 0.085, blue: 0.07) : Color(red: 0.97, green: 0.98, blue: 0.92)
    }
    private var ink: Color {
        dark ? Color(red: 0.93, green: 0.97, blue: 0.85) : Color(red: 0.07, green: 0.13, blue: 0.10)
    }
    private var lime: Color {
        dark ? Color(red: 0.71, green: 0.91, blue: 0.28) : Color(red: 0.81, green: 0.94, blue: 0.36)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)

                    poster
                        .frame(height: min(geometry.size.width * 1.02, 470))
                        .accessibilityHidden(true)

                    Spacer(minLength: 32)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Room to breathe.")
                            .font(.system(size: titleSize, weight: .black))
                            .tracking(-2)
                            .accessibilityAddTraits(.isHeader)
                        Text("Less clutter. More space.")
                            .font(.body)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(ink)
        .background(paper.ignoresSafeArea())
    }

    private var masthead: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                wordmark
                Spacer(minLength: 16)
                descriptor
            }
            VStack(alignment: .leading, spacing: 6) {
                wordmark
                descriptor
            }
        }
    }

    private var wordmark: some View {
        Text(verbatim: "Filevra")
            .font(.title2.weight(.black))
    }

    private var descriptor: some View {
        Text("DEVICE CLEANUP")
            .font(.caption2.weight(.bold))
            .tracking(2)
    }

    private var poster: some View {
        Canvas { context, size in
            let unit = max(size.width, size.height) / 400
            let forest = Color(red: 0.08, green: 0.20, blue: 0.13)
            let mint = Color(red: 0.53, green: 0.79, blue: 0.67)
            var art = context
            art.translateBy(x: size.width / 2, y: size.height / 2)
            art.scaleBy(x: unit, y: unit)

            var fold = Path()
            fold.move(to: CGPoint(x: -220, y: 220))
            fold.addLine(to: CGPoint(x: 220, y: -158))
            fold.addLine(to: CGPoint(x: 220, y: 220))
            fold.closeSubpath()
            art.fill(fold, with: .color(forest))

            var folder = Path()
            folder.move(to: CGPoint(x: -135, y: 98))
            folder.addLine(to: CGPoint(x: -135, y: -88))
            folder.addLine(to: CGPoint(x: -47, y: -88))
            folder.addLine(to: CGPoint(x: -18, y: -58))
            folder.addLine(to: CGPoint(x: 119, y: -58))
            folder.addLine(to: CGPoint(x: 119, y: 98))
            folder.closeSubpath()

            var folderLayer = art
            folderLayer.rotate(by: .degrees(-12))
            folderLayer.fill(folder, with: .color(mint))

            // Cut a square out of the pocket to reveal the layer beneath it.
            var pocket = Path(CGRect(x: -116, y: -28, width: 250, height: 136))
            pocket.addRect(CGRect(x: 24, y: 10, width: 66, height: 66))
            folderLayer.fill(pocket, with: .color(paper), style: FillStyle(eoFill: true))

            var tile = art
            tile.translateBy(x: 121, y: -111)
            tile.rotate(by: .degrees(22))
            tile.fill(Path(CGRect(x: -27, y: -27, width: 54, height: 54)),
                      with: .color(forest))
        }
        .background(lime)
        .clipped()
    }
}

#Preview("Cutout · Light") {
    CutoutLaunchScreen()
        .preferredColorScheme(.light)
}

#Preview("Cutout · Dark") {
    CutoutLaunchScreen()
        .preferredColorScheme(.dark)
}
#endif
