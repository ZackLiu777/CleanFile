#if DEBUG
import SwiftUI

private struct ReceiptLaunchScreen: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let dark = scheme == .dark
        let stock = dark ? Color(white: 0.16) : Color(white: 0.99)
        let ink = dark ? Color(white: 0.97) : Color(white: 0.13)
        let stamp = dark ? Color(red: 1, green: 0.72, blue: 0.49)
                         : Color(red: 0.63, green: 0.26, blue: 0.06)

        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("FILE UTILITY", systemImage: "tray")
                        .font(.caption.monospaced().weight(.semibold))
                    rule
                    Text(verbatim: "Filevra")
                        .font(.largeTitle.monospaced().weight(.black))
                        .accessibilityAddTraits(.isHeader)
                    Text("Make room for more.")
                        .font(.body.monospaced())
                    rule
                    Image(systemName: "barcode")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 102, height: 32)
                        .foregroundStyle(stamp)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
                .foregroundStyle(ink)
                .background(stock)
                .overlay(alignment: .bottom) {
                    Canvas { context, size in
                        for x in stride(from: 0.0, to: size.width, by: 12) {
                            var notch = Path()
                            notch.move(to: CGPoint(x: x, y: 6))
                            notch.addLine(to: CGPoint(x: x + 6, y: 0))
                            notch.addLine(to: CGPoint(x: x + 12, y: 6))
                            notch.closeSubpath()
                            context.fill(notch, with: .color(stock))
                        }
                    }
                    .frame(height: 6)
                    .offset(y: 6)
                    .accessibilityHidden(true)
                }
                .shadow(color: reduceTransparency ? .clear : .black.opacity(0.18), radius: 20, y: 14)
                .frame(maxWidth: 340)
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            (dark ? Color(white: 0.07) : Color(white: 0.86)).ignoresSafeArea()
        }
    }

    private var rule: some View {
        Canvas { context, size in
            var line = Path()
            line.move(to: CGPoint(x: 0, y: 1))
            line.addLine(to: CGPoint(x: size.width, y: 1))
            context.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

private struct SignalLaunchScreen: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize = 76

    var body: some View {
        let dark = scheme == .dark
        let ground = dark ? Color(red: 0.18, green: 0.07, blue: 0.13)
                          : Color(red: 1, green: 0.89, blue: 0.92)
        let ink = dark ? Color(red: 1, green: 0.91, blue: 0.94)
                       : Color(red: 0.30, green: 0.07, blue: 0.19)
        let band = dark ? Color(red: 1, green: 0.48, blue: 0.67)
                        : Color(red: 0.56, green: 0.10, blue: 0.32)

        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DEVICE CLEANUP")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .padding(24)
                    Spacer(minLength: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Filevra")
                            .font(.system(size: wordmarkSize, weight: .black).width(.condensed))
                            .accessibilityAddTraits(.isHeader)
                        Text("Clear the way.")
                            .font(.title3.weight(.semibold))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(dark ? ground : .white)
                    .background(band)

                    SignalStripes(color: band)
                        .frame(height: 92)
                        .accessibilityHidden(true)
                    Spacer(minLength: 32)
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(ink)
        .background(ground.ignoresSafeArea())
    }
}

private struct SignalStripes: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            for (offset, height) in [(0.0, 28.0), (39, 15), (64, 7), (81, 3)] {
                var stripe = Path()
                stripe.move(to: CGPoint(x: 0, y: offset))
                stripe.addLine(to: CGPoint(x: size.width, y: offset))
                stripe.addLine(to: CGPoint(x: size.width, y: offset + height * 0.35))
                stripe.addLine(to: CGPoint(x: 0, y: offset + height))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(color))
            }
        }
    }
}

#Preview("Receipt · Light") {
    ReceiptLaunchScreen().preferredColorScheme(.light)
}

#Preview("Receipt · Dark") {
    ReceiptLaunchScreen().preferredColorScheme(.dark)
}

#Preview("Signal · Light") {
    SignalLaunchScreen().preferredColorScheme(.light)
}

#Preview("Signal · Dark") {
    SignalLaunchScreen().preferredColorScheme(.dark)
}
#endif
