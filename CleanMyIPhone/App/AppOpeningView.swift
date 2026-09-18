import SwiftUI

enum AppOpeningEffect: CaseIterable, Identifiable {
    case fileFlow
    case mosaic
    case orbitalSort
    case conveyor

    var id: Self { self }

    var previewName: String {
        switch self {
        case .fileFlow: "文件流归档"
        case .mosaic: "像素拼图"
        case .orbitalSort: "环形分拣"
        case .conveyor: "传送带"
        }
    }
}

/// The same opening artwork can be previewed independently or hosted by the startup flow.
struct AppOpeningView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var effect: AppOpeningEffect = .fileFlow
    var animationsEnabled = true
    @State private var startedAt = Date()

    private var animates: Bool {
        animationsEnabled && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.76, geometry.size.height * 0.43, 340)
            ZStack {
                theme.backgroundPrimary.ignoresSafeArea()
                AppBackground()
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
                    let elapsed = animates ? context.date.timeIntervalSince(startedAt) : 1.7
                    openingArtwork(time: min(elapsed, 2), diameter: diameter)
                        .frame(width: diameter, height: diameter)
                }
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func openingArtwork(time: Double, diameter: CGFloat) -> some View {
        switch effect {
        case .fileFlow:
            fileFlowArtwork(time: time, diameter: diameter)
        case .mosaic:
            mosaicArtwork(time: time, diameter: diameter)
        case .orbitalSort:
            orbitalSortArtwork(time: time, diameter: diameter)
        case .conveyor:
            conveyorArtwork(time: time, diameter: diameter)
        }
    }

    private func fileFlowArtwork(time: Double, diameter: CGFloat) -> some View {
        let completion = smoothStep(clamped((time - 1.18) / 0.36))
        let settle = sin(completion * .pi)
        let entryPoints: [(x: Double, y: Double)] = [
            (-0.56, -0.48), (0.58, -0.22), (-0.58, 0.26), (0.52, 0.52)
        ]

        return ZStack {
            Circle()
                .stroke(theme.accentPrimary.opacity(0.08), lineWidth: 1)
                .frame(width: diameter * 0.82, height: diameter * 0.82)
                .scaleEffect(0.92 + completion * 0.08)

            Circle()
                .fill(theme.accentPrimary.opacity(0.08))
                .frame(width: diameter * 0.58, height: diameter * 0.58)
                .blur(radius: 28)
                .scaleEffect(0.88 + completion * 0.12)

            ForEach(0..<4) { index in
                let progress = smoothStep(clamped((time - Double(index) * 0.10) / 0.92))
                let start = entryPoints[index]
                let destinationY = (Double(index) - 1.5) * 0.135
                let curve = sin(progress * .pi) * (index.isMultiple(of: 2) ? -0.10 : 0.10)

                fileSlip(index: index, diameter: diameter)
                    .rotationEffect(.degrees((1 - progress) * (index.isMultiple(of: 2) ? -18 : 18)))
                    .scaleEffect(0.92 + progress * 0.08 - settle * 0.025)
                    .offset(
                        x: diameter * (start.x * (1 - progress) + curve),
                        y: diameter * (start.y * (1 - progress) + destinationY * progress)
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
                        x: cos(angle) * diameter * 0.31 * burst,
                        y: sin(angle) * diameter * 0.31 * burst
                    )
                    .opacity(completion > 0 ? 1 : 0)
            }

            Capsule()
                .fill(theme.accentPrimary.opacity(0.55 * completion))
                .frame(width: diameter * 0.24, height: 2)
                .offset(y: diameter * 0.34)
                .scaleEffect(x: completion, anchor: .center)
        }
    }

    private func fileSlip(index: Int, diameter: CGFloat) -> some View {
        let symbols = ["photo", "film", "waveform", "doc.text"]

        return HStack(spacing: diameter * 0.035) {
            Image(systemName: symbols[index])
                .font(.system(size: diameter * 0.047, weight: .medium))
                .foregroundStyle(theme.accentPrimary)
                .frame(width: diameter * 0.09)

            VStack(alignment: .leading, spacing: diameter * 0.018) {
                Capsule()
                    .fill(theme.textPrimary.opacity(0.34))
                    .frame(width: diameter * (0.17 + CGFloat(index % 2) * 0.045), height: 3)
                Capsule()
                    .fill(theme.textSecondary.opacity(0.18))
                    .frame(width: diameter * 0.12, height: 2)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(theme.accentPrimary.opacity(0.20))
                .frame(width: diameter * 0.035, height: diameter * 0.035)
        }
        .padding(.horizontal, diameter * 0.045)
        .frame(width: diameter * 0.50, height: diameter * 0.115)
        .background(
            theme.cardSurface.opacity(0.82),
            in: RoundedRectangle(cornerRadius: diameter * 0.035, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: diameter * 0.035, style: .continuous)
                .strokeBorder(theme.divider.opacity(0.45), lineWidth: 0.5)
        }
        .shadow(color: theme.accentPrimary.opacity(0.07), radius: 10, y: 5)
    }

    private func mosaicArtwork(time: Double, diameter: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: diameter * 0.12, style: .continuous)
                .fill(theme.accentPrimary.opacity(0.055))
                .frame(width: diameter * 0.72, height: diameter * 0.72)
                .rotationEffect(.degrees(45))

            ForEach(0..<9) { index in
                let row = index / 3
                let column = index % 3
                let progress = smoothStep(clamped((time - Double(index) * 0.055) / 0.72))
                let targetX = (Double(column) - 1) * 0.19
                let targetY = (Double(row) - 1) * 0.19
                let startAngle = Double(index) * 0.78
                let startRadius = 0.66 + Double(index % 3) * 0.07

                mosaicTile(index: index, diameter: diameter)
                    .scaleEffect(0.52 + progress * 0.48)
                    .rotationEffect(.degrees((1 - progress) * Double(index.isMultiple(of: 2) ? -34 : 34)))
                    .offset(
                        x: diameter * (cos(startAngle) * startRadius * (1 - progress) + targetX * progress),
                        y: diameter * (sin(startAngle) * startRadius * (1 - progress) + targetY * progress)
                    )
                    .opacity(0.15 + progress * 0.85)
            }

            RoundedRectangle(cornerRadius: diameter * 0.06, style: .continuous)
                .stroke(theme.accentPrimary.opacity(0.35 * clamped((time - 1.1) / 0.35)), lineWidth: 1.5)
                .frame(width: diameter * 0.59, height: diameter * 0.59)
                .scaleEffect(0.9 + clamped((time - 1.1) / 0.35) * 0.1)
        }
    }

    private func mosaicTile(index: Int, diameter: CGFloat) -> some View {
        let symbols = ["photo", "film", "waveform", "doc.text"]
        return RoundedRectangle(cornerRadius: diameter * 0.035, style: .continuous)
            .fill(theme.cardSurface.opacity(0.88))
            .frame(width: diameter * 0.16, height: diameter * 0.16)
            .overlay {
                Image(systemName: symbols[index % symbols.count])
                    .font(.system(size: diameter * 0.045, weight: .medium))
                    .foregroundStyle(theme.accentPrimary.opacity(index == 4 ? 1 : 0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: diameter * 0.035, style: .continuous)
                    .strokeBorder(theme.divider.opacity(0.4), lineWidth: 0.5)
            }
            .shadow(color: theme.accentPrimary.opacity(0.06), radius: 8, y: 4)
    }

    private func orbitalSortArtwork(time: Double, diameter: CGFloat) -> some View {
        let completion = smoothStep(clamped((time - 1.05) / 0.42))
        let symbols = ["photo", "film", "waveform", "doc.text"]

        return ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .stroke(
                        theme.accentPrimary.opacity(0.08 + Double(ring) * 0.025),
                        style: StrokeStyle(lineWidth: 1, dash: ring == 1 ? [3, 8] : [])
                    )
                    .frame(
                        width: diameter * (0.34 + CGFloat(ring) * 0.2),
                        height: diameter * (0.34 + CGFloat(ring) * 0.2)
                    )
                    .rotationEffect(.degrees(time * (ring.isMultiple(of: 2) ? 28 : -22)))
            }

            ForEach(0..<8) { index in
                let delay = Double(index) * 0.045
                let progress = smoothStep(clamped((time - delay) / 1.05))
                let angle = Double(index) * .pi / 4 + time * (index.isMultiple(of: 2) ? 0.45 : -0.35)
                let orbitRadius = 0.29 + Double(index % 3) * 0.075
                let finalRadius = index < 4 ? 0.15 : 0.24
                let radius = orbitRadius * (1 - completion) + finalRadius * completion

                Circle()
                    .fill(theme.cardSurface.opacity(0.9))
                    .frame(width: diameter * 0.13, height: diameter * 0.13)
                    .overlay {
                        Image(systemName: symbols[index % symbols.count])
                            .font(.system(size: diameter * 0.038, weight: .medium))
                            .foregroundStyle(theme.accentPrimary)
                    }
                    .overlay {
                        Circle().strokeBorder(theme.divider.opacity(0.4), lineWidth: 0.5)
                    }
                    .shadow(color: theme.accentPrimary.opacity(0.07), radius: 8, y: 4)
                    .offset(
                        x: cos(angle) * diameter * radius * progress,
                        y: sin(angle) * diameter * radius * progress
                    )
                    .scaleEffect(0.55 + progress * 0.45)
                    .opacity(progress)
            }

            Circle()
                .fill(theme.accentPrimary.opacity(0.10 + completion * 0.05))
                .frame(width: diameter * 0.10, height: diameter * 0.10)
                .scaleEffect(0.8 + sin(time * 3) * 0.08)
        }
    }

    private func conveyorArtwork(time: Double, diameter: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3) { lane in
                Capsule()
                    .fill(theme.divider.opacity(0.22))
                    .frame(width: diameter * 0.82, height: 1)
                    .offset(y: (CGFloat(lane) - 1) * diameter * 0.19)
            }

            ForEach(0..<6) { index in
                let lane = index % 3
                let progress = smoothStep(clamped((time - Double(index) * 0.075) / 0.9))
                let targetX = (Double(index / 3) - 0.5) * 0.20
                let targetY = (Double(lane) - 1) * 0.19
                let startX = index.isMultiple(of: 2) ? -0.62 : 0.62

                compactFile(index: index, diameter: diameter)
                    .offset(
                        x: diameter * (startX * (1 - progress) + targetX * progress),
                        y: diameter * targetY
                    )
                    .scaleEffect(0.86 + progress * 0.14)
                    .opacity(0.25 + progress * 0.75)
            }

            ForEach(0..<5) { index in
                let pulse = clamped((time - 1.15 - Double(index) * 0.06) / 0.36)
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.accentPrimary.opacity(0.45 * (1 - pulse)))
                    .frame(width: 3, height: 8)
                    .rotationEffect(.degrees(Double(index) * 72))
                    .offset(
                        x: cos(Double(index) * .pi * 0.4) * diameter * 0.25 * pulse,
                        y: sin(Double(index) * .pi * 0.4) * diameter * 0.25 * pulse
                    )
            }
        }
    }

    private func compactFile(index: Int, diameter: CGFloat) -> some View {
        let symbols = ["photo", "film", "waveform", "doc.text"]
        return RoundedRectangle(cornerRadius: diameter * 0.025, style: .continuous)
            .fill(theme.cardSurface.opacity(0.9))
            .frame(width: diameter * 0.16, height: diameter * 0.13)
            .overlay {
                Image(systemName: symbols[index % symbols.count])
                    .font(.system(size: diameter * 0.04, weight: .medium))
                    .foregroundStyle(theme.accentPrimary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: diameter * 0.025, style: .continuous)
                    .strokeBorder(theme.divider.opacity(0.45), lineWidth: 0.5)
            }
            .shadow(color: theme.accentPrimary.opacity(0.06), radius: 7, y: 3)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}

/// Keeps startup presentation separate from the application's navigation and business state.
struct AppOpeningContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsOpening: Bool
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        let arguments = ProcessInfo.processInfo.arguments
        _showsOpening = State(initialValue: !arguments.contains { $0.hasPrefix("--ui-test") })
    }

    var body: some View {
        ZStack {
            content
            if showsOpening {
                AppOpeningView(animationsEnabled: !reduceMotion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task(id: showsOpening) {
            guard showsOpening else { return }
            let duration: Duration = reduceMotion ? .milliseconds(450) : .milliseconds(2050)
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.32)) {
                showsOpening = false
            }
        }
    }
}

#if DEBUG
/// Preview controls stay outside production UI and never write saved user preferences.
private struct AppOpeningPreview: View {
    let effect: AppOpeningEffect
    @State private var themeID: AppThemeID = .cream
    @State private var animations = true
    @State private var replayID = UUID()

    var body: some View {
        let previewTheme = themeID.theme
        AppOpeningView(effect: effect, animationsEnabled: animations)
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
                    Toggle("Motion", isOn: $animations).fixedSize()
                    Button("Replay") { replayID = UUID() }
                }
                .font(.caption)
                .padding(12)
                .background(.regularMaterial)
            }
    }
}

#Preview("A · 文件流归档") { AppOpeningPreview(effect: .fileFlow) }
#Preview("B · 像素拼图") { AppOpeningPreview(effect: .mosaic) }
#Preview("C · 环形分拣") { AppOpeningPreview(effect: .orbitalSort) }
#Preview("D · 传送带") { AppOpeningPreview(effect: .conveyor) }
#Preview("iPad · 文件流归档", traits: .fixedLayout(width: 834, height: 1194)) {
    AppOpeningPreview(effect: .fileFlow)
}
#Preview("静态效果") {
    AppOpeningView(effect: .mosaic, animationsEnabled: false)
        .environment(\.appTheme, Theme.cream)
        .appFontFamily("Georgia")
}
#endif
