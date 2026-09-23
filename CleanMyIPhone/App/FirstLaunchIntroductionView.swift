import ImageFormatConversionKit
import SwiftUI

/// The introduction uses bundled sample data; it never reads or changes the user's files.
struct FirstLaunchIntroductionContainer<Content: View>: View {
    @AppStorage("hasCompletedFirstLaunchIntroduction") private var hasCompletedIntroduction = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shouldShowIntroduction: Bool {
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test") }) { return false }
        return !hasCompletedIntroduction
    }

    var body: some View {
        Group {
            if shouldShowIntroduction {
                FirstLaunchIntroductionView {
                    hasCompletedIntroduction = true
                }
            } else {
                content
            }
        }
    }
}

private enum IntroductionPage: Int, CaseIterable {
    case media, files, compress, appearance

    var title: LocalizedStringKey {
        switch self {
        case .media: "intro.media.title"
        case .files: "intro.files.title"
        case .compress: "intro.compress.title"
        case .appearance: "intro.appearance.title"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .media: "intro.media.detail"
        case .files: "intro.files.detail"
        case .compress: "intro.compress.detail"
        case .appearance: "intro.appearance.detail"
        }
    }

    var icon: String {
        switch self {
        case .media: "photo.on.rectangle.angled"
        case .files: "folder"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .appearance: "paintpalette"
        }
    }
}

struct FirstLaunchIntroductionView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = 0
    @State private var animationOrigin = Date()
    let onComplete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Text("CleanFile")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text("\(page + 1) / 4")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.top, 18)

                TabView(selection: $page) {
                    ForEach(IntroductionPage.allCases, id: \.rawValue) { item in
                        VStack(spacing: 18) {
                            Spacer(minLength: 10)
                            TimelineView(.animation(minimumInterval: 1.0 / 24,
                                                    paused: reduceMotion || scenePhase != .active || page != item.rawValue)) { context in
                                let phase = reduceMotion ? 0.55 : max(0, context.date.timeIntervalSince(animationOrigin))
                                IntroductionArtwork(page: item, phase: phase)
                                    .frame(height: min(geometry.size.height * 0.54, 445))
                            }
                            .accessibilityHidden(true)
                            Text(item.title)
                                .appTypeface(.largeTitle.bold(), size: 31, relativeTo: .largeTitle, weight: .bold)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.75)
                            Text(item.detail)
                                .font(.body)
                                .foregroundStyle(theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                        }
                        .padding(.horizontal, 8)
                        .tag(item.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 9) {
                    ForEach(0..<4) { index in
                        Capsule()
                            .fill(index == page ? theme.accentPrimary : theme.textTertiary.opacity(0.45))
                            .frame(width: index == page ? 25 : 8, height: 8)
                    }
                }
                .accessibilityLabel("\(page + 1) of 4")
                .padding(.bottom, 24)

                Button {
                    if page == 3 {
                        onComplete()
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(page == 3 ? "intro.start" : "intro.next")
                        Image(systemName: page == 3 ? "checkmark" : "arrow.right")
                    }
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(theme.textInverted)
                    .background(theme.buttonPrimaryBackground, in: RoundedRectangle(cornerRadius: 18))
                }
                .accessibilityIdentifier("intro.continue")
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                AppBackground()
                    .ignoresSafeArea()
            }
        }
        .onChange(of: page) { _, _ in animationOrigin = Date() }
    }
}

private struct IntroductionArtwork: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: IntroductionPage
    let phase: TimeInterval

    private var step: Int { Int(phase.truncatingRemainder(dividingBy: 6) / 1.5) }
    private let appearancePalettes: [AppAccentPaletteID] = [.pink, .coral, .gold, .sage, .sky, .teal, .berry]
    private var appearanceIndex: Int {
        reduceMotion ? 0 : Int(phase / 0.85) % appearancePalettes.count
    }
    private var appearanceAccent: Color {
        appearancePalettes[appearanceIndex].color ?? theme.accentPrimary
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: page.icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(theme.accentPrimary)
                .symbolEffect(.pulse, options: .repeating, isActive: step == 2)
            switch page {
            case .media: mediaArtwork
            case .files: filesArtwork
            case .compress: compressArtwork
            case .appearance: appearanceArtwork
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(page == .appearance ? appearanceAccent.opacity(0.12) : theme.cardSurface,
                    in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(theme.divider, lineWidth: 1))
        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: step)
        .animation(.easeInOut(duration: 0.4), value: appearanceIndex)
    }

    private var mediaArtwork: some View {
        VStack(spacing: 12) {
            Text("intro.demo")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            MediaStorageOverview(
                storage: DeviceStorageSnapshot(totalBytes: 128_000_000_000, availableBytes: 38_000_000_000),
                photoBytes: 25_000_000_000,
                videoBytes: 12_000_000_000,
                animatedUsedFraction: step == 0 ? 0 : 90.0 / 128.0,
                animationsEnabled: true
            )

            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Image(systemName: ["photo", "video", "photo.stack"][index])
                        .font(.title3)
                        .foregroundStyle(theme.accentPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topTrailing) {
                            if step >= 2 && index != 1 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.accentPrimary)
                                    .padding(4)
                            }
                        }
                        .opacity(step == 3 && index != 1 ? 0.4 : 1)
                }
            }
        }
    }

    private var filesArtwork: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Folder Map", systemImage: "circle.hexagongrid")
                    .font(.headline)
                Spacer()
                Text("intro.demo")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            SunburstChartView(
                root: Self.sampleFolderTree,
                revealProgress: reduceMotion ? 1 : min(1, Double(phase) / 2.5)
            )
            .frame(height: 265)
            .allowsHitTesting(false)
        }
    }

    private static let sampleFolderTree: FileNode = {
        // A fixed, in-memory hierarchy gives the introduction the same dense
        // multi-ring chart as a scanned folder without inspecting user files.
        func branch(id: String, bytes: Int64, depth: Int, category: FileCategory) -> FileNode {
            guard depth < 6 else {
                return FileNode(id: id, name: id, byteCount: bytes,
                                children: [], category: category, isDirectory: false)
            }
            let weights: [Int64] = depth.isMultiple(of: 2) ? [5, 3, 2] : [4, 3, 2, 1]
            let total = weights.reduce(0, +)
            var allocated: Int64 = 0
            let children = weights.enumerated().map { index, weight in
                let childBytes = index == weights.count - 1
                    ? bytes - allocated : bytes * weight / total
                allocated += childBytes
                return branch(id: "\(id).\(index)", bytes: childBytes,
                              depth: depth + 1, category: category)
            }
            return FileNode(id: id, name: id, byteCount: bytes,
                            children: children, category: nil, isDirectory: true)
        }

        let groups: [(String, Int64, FileCategory)] = [
            ("images", 410_000_000, .image),
            ("videos", 320_000_000, .video),
            ("documents", 160_000_000, .document),
            ("audio", 70_000_000, .audio)
        ]
        return FileNode(
            id: "intro.folder", name: "Sample", byteCount: 960_000_000,
            children: groups.map { name, bytes, category in
                branch(id: "intro.\(name)", bytes: bytes, depth: 1, category: category)
            },
            category: nil, isDirectory: true
        )
    }()

    private var compressArtwork: some View {
        VStack(spacing: 22) {
            ConversionIntroductionPreview(theme: theme.conversionTheme, step: step)
                .frame(height: 230)

            let progress = reduceMotion ? 1 : phase.truncatingRemainder(dividingBy: 4) / 4
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .foregroundStyle(theme.accentPrimary)
                WaveProgressView(progress: progress, height: 12, tint: theme.accentPrimary)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(theme.accentPrimary)
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(.horizontal, 12)
        }
    }

    private var appearanceArtwork: some View {
        return VStack(spacing: 22) {
            AppearanceThemePreview(previewTint: appearanceAccent)
                .environment(\.appTheme, theme.applyingAccent(appearanceAccent))
            HStack(spacing: 10) {
                ForEach(appearancePalettes.indices, id: \.self) { index in
                    Circle()
                        .fill(appearancePalettes[index].color ?? theme.accentPrimary)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .stroke(theme.textPrimary, lineWidth: appearanceIndex == index ? 2 : 0)
                                .padding(-4)
                        }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
