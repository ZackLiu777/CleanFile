import SwiftUI

/// Isolated from the startup host so this animation can be previewed and tuned directly.
struct FileFlowOpeningArtwork: View {
    @Environment(\.appTheme) private var theme
    let time: Double
    let size: CGFloat

    private let entryPoints: [(x: Double, y: Double)] = [
        (-0.56, -0.48), (0.58, -0.22), (-0.58, 0.26), (0.52, 0.52)
    ]

    var body: some View {
        let completion = smoothStep(clamped((time - 1.18) / 0.36))
        let settle = sin(completion * .pi)

        ZStack {
            Circle()
                .stroke(theme.accentPrimary.opacity(0.08), lineWidth: 1)
                .frame(width: size * 0.82, height: size * 0.82)
                .scaleEffect(0.92 + completion * 0.08)

            Circle()
                .fill(theme.accentPrimary.opacity(0.08))
                .frame(width: size * 0.58, height: size * 0.58)
                .blur(radius: 28)
                .scaleEffect(0.88 + completion * 0.12)

            ForEach(0..<4) { index in
                let progress = smoothStep(clamped((time - Double(index) * 0.10) / 0.92))
                let start = entryPoints[index]
                let destinationY = (Double(index) - 1.5) * 0.135
                let curve = sin(progress * .pi) * (index.isMultiple(of: 2) ? -0.10 : 0.10)

                fileSlip(index: index)
                    .rotationEffect(.degrees((1 - progress) * (index.isMultiple(of: 2) ? -18 : 18)))
                    .scaleEffect(0.92 + progress * 0.08 - settle * 0.025)
                    .offset(
                        x: size * (start.x * (1 - progress) + curve),
                        y: size * (start.y * (1 - progress) + destinationY * progress)
                    )
                    .opacity(0.35 + progress * 0.65)
            }

            ForEach(0..<8) { index in
                let burst = clamped((time - 1.42 - Double(index) * 0.018) / 0.42)
                let angle = Double(index) * .pi / 4

                Circle()
                    .fill(theme.accentPrimary.opacity(0.5 * (1 - burst)))
                    .frame(width: index.isMultiple(of: 2) ? 5 : 3, height: index.isMultiple(of: 2) ? 5 : 3)
                    .offset(
                        x: cos(angle) * size * 0.31 * burst,
                        y: sin(angle) * size * 0.31 * burst
                    )
                    .opacity(completion > 0 ? 1 : 0)
            }

            Capsule()
                .fill(theme.accentPrimary.opacity(0.55 * completion))
                .frame(width: size * 0.24, height: 2)
                .offset(y: size * 0.34)
                .scaleEffect(x: completion, anchor: .center)
        }
    }

    private func fileSlip(index: Int) -> some View {
        let symbols = ["photo", "film", "waveform", "doc.text"]

        return HStack(spacing: size * 0.035) {
            Image(systemName: symbols[index])
                .font(.system(size: size * 0.047, weight: .medium))
                .foregroundStyle(theme.accentPrimary)
                .frame(width: size * 0.09)

            VStack(alignment: .leading, spacing: size * 0.018) {
                Capsule()
                    .fill(theme.textPrimary.opacity(0.34))
                    .frame(width: size * (0.17 + CGFloat(index % 2) * 0.045), height: 3)
                Capsule()
                    .fill(theme.textSecondary.opacity(0.18))
                    .frame(width: size * 0.12, height: 2)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(theme.accentPrimary.opacity(0.20))
                .frame(width: size * 0.035, height: size * 0.035)
        }
        .padding(.horizontal, size * 0.045)
        .frame(width: size * 0.50, height: size * 0.115)
        .appContentCard(cornerRadius: size * 0.035)
        .shadow(color: theme.accentPrimary.opacity(0.07), radius: 10, y: 5)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}

#if DEBUG
private struct FileFlowOpeningPreview: View {
    @State private var themeID: AppThemeID = .cream
    @State private var animationsEnabled = true
    @State private var liquidGlassEnabled = true
    @State private var replayID = UUID()

    var body: some View {
        let previewTheme = themeID.theme.applyingLiquidGlassCards(liquidGlassEnabled)

        AppOpeningView(animationsEnabled: animationsEnabled)
            .id(replayID)
            .environment(\.appTheme, previewTheme)
            .appFontFamily("Georgia")
            .preferredColorScheme(previewTheme.preferredColorScheme)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Picker("Theme", selection: $themeID) {
                        ForEach(AppThemeID.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    Toggle("Glass", isOn: $liquidGlassEnabled)
                        .fixedSize()
                    Toggle("Motion", isOn: $animationsEnabled)
                        .fixedSize()
                    Button("Replay") {
                        replayID = UUID()
                    }
                }
                .font(.caption)
                .padding(12)
                .background(.regularMaterial)
            }
    }
}

#Preview("文件流归档 · iPhone") {
    FileFlowOpeningPreview()
}

#Preview("文件流归档 · iPad", traits: .fixedLayout(width: 834, height: 1194)) {
    FileFlowOpeningPreview()
}

#Preview("文件流归档 · 完成状态") {
    ZStack {
        Theme.cream.backgroundPrimary.ignoresSafeArea()
        AppBackground()
        FileFlowOpeningArtwork(time: 2, size: 340)
    }
    .environment(\.appTheme, Theme.cream)
    .appFontFamily("Georgia")
}
#endif
