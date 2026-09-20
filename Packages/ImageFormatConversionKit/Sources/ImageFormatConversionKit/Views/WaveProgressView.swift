import SwiftUI

/// A compact animated progress indicator shared by media analysis, import,
/// and conversion surfaces.
public struct WaveProgressView: View {
    private let progress: Double
    private let height: CGFloat
    private let tint: Color
    @State private var waveOffset: Angle = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Double, height: CGFloat = 12, tint: Color = .accentColor) {
        self.progress = min(max(progress, 0), 1)
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.06))

                WaveProgressShape(
                    offset: waveOffset,
                    waveHeight: min(2, height * 0.2)
                )
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.72),
                            tint
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geometry.size.width * progress)
                .clipShape(Capsule())
                .shadow(
                    color: tint.opacity(0.3),
                    radius: 3,
                    y: 1
                )
                .animation(.easeOut(duration: 0.18), value: progress)
            }
        }
        .frame(height: height)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                waveOffset = .degrees(360)
            }
        }
    }
}

private struct WaveProgressShape: Shape {
    var offset: Angle
    let waveHeight: CGFloat

    var animatableData: Double {
        get { offset.degrees }
        set { offset = .degrees(newValue) }
    }

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))

        for x in stride(from: CGFloat.zero, through: rect.width, by: 2) {
            let phase = x / rect.width * .pi * 4 + offset.radians
            let y = rect.height / 2 + sin(phase) * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}
