//
//  ConversionHomeView.swift
//
//  文件职责：声明 ConversionHome 界面结构、交互入口与展示状态。
//  所属模块：ImageFormatConversionKit.
//

import SwiftUI

@MainActor
public struct ConversionHomeView: View {
    private let theme: ConversionTheme
    private let isTabActive: Bool
    @State private var recentRecords: [ConversionHomeKind: ConversionHomeRecord] = [:]
    @State private var imageViewModel: ImageConversionViewModel
    @State private var videoViewModel: VideoConversionViewModel
    @State private var audioViewModel: AudioConversionViewModel
    @State private var imageImportSession: ConversionImportSession
    @State private var videoImportSession: ConversionImportSession
    @State private var audioImportSession: ConversionImportSession
    @State private var isHomeContentVisible = false
    @State private var entranceGeneration = 0
    @State private var hasAppeared = false
    @Namespace private var navigationTransitionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        theme: ConversionTheme = .system,
        isTabActive: Bool = true
    ) {
        self.theme = theme
        self.isTabActive = isTabActive
        _imageViewModel = State(initialValue: ImageConversionViewModel())
        _videoViewModel = State(initialValue: VideoConversionViewModel())
        _audioViewModel = State(initialValue: AudioConversionViewModel())
        _imageImportSession = State(initialValue: ConversionImportSession())
        _videoImportSession = State(initialValue: ConversionImportSession())
        _audioImportSession = State(initialValue: ConversionImportSession())
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(L10n.string("converter.heading"))
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, -12)
                    .padding(.bottom, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(
                            Array(ConversionHomeKind.allCases.enumerated()),
                            id: \.element
                        ) { index, kind in
                            NavigationLink(value: kind) {
                                ConversionHomeCard(
                                    kind: kind,
                                    recentRecord: recentRecords[kind]
                                )
                                .conversionMatchedTransitionSource(
                                    id: kind,
                                    in: navigationTransitionNamespace,
                                    enabled: !reduceMotion
                                )
                            }
                            .buttonStyle(
                                ConversionHomeCardButtonStyle(
                                    reduceMotion: reduceMotion
                                )
                            )
                            .modifier(
                                ConversionHomeStaggeredAppear(
                                    isVisible: isHomeContentVisible,
                                    index: index,
                                    reduceMotion: reduceMotion
                                )
                            )
                        }

                        Label(
                            L10n.string("import.subtitle"),
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                        .modifier(
                            ConversionHomeStaggeredAppear(
                                isVisible: isHomeContentVisible,
                                index: ConversionHomeKind.allCases.count,
                                reduceMotion: reduceMotion
                            )
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .converterSoftScrollEdge()
            }
            .background(converterBackground)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ConversionHomeKind.self) { kind in
                ConversionToolDestination(
                    kind: kind,
                    imageViewModel: imageViewModel,
                    videoViewModel: videoViewModel,
                    audioViewModel: audioViewModel,
                    imageImportSession: imageImportSession,
                    videoImportSession: videoImportSession,
                    audioImportSession: audioImportSession
                )
                .conversionNavigationTransition(
                    sourceID: kind,
                    in: navigationTransitionNamespace,
                    enabled: !reduceMotion
                )
            }
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    if isTabActive {
                        playEntrance()
                    }
                }
                loadRecentRecords()
            }
            .onChange(of: isTabActive) { _, isActive in
                if isActive {
                    playEntrance()
                } else {
                    cancelAndResetEntrance()
                }
            }
        }
        .environment(\.conversionTheme, theme)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
    }

    @ViewBuilder
    private var converterBackground: some View {
        switch theme.background {
        case let .solid(color):
            color.ignoresSafeArea()
        case let .linearGradient(colors, startPoint, endPoint):
            LinearGradient(
                colors: colors,
                startPoint: startPoint,
                endPoint: endPoint
            )
            .ignoresSafeArea()
        }
    }

    private func playEntrance() {
        guard isTabActive else { return }
        entranceGeneration &+= 1
        let generation = entranceGeneration
        resetEntranceWithoutAnimation()

        guard !reduceMotion else {
            isHomeContentVisible = true
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard isTabActive else { return }
            guard generation == entranceGeneration else { return }
            isHomeContentVisible = true
        }
    }

    private func cancelAndResetEntrance() {
        entranceGeneration &+= 1
        resetEntranceWithoutAnimation()
    }

    private func resetEntranceWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isHomeContentVisible = false
        }
    }

    private func loadRecentRecords() {
        Task {
            let loadedRecords = await ConversionHomeHistoryLoader.shared.load()
            guard !Task.isCancelled else { return }

            if reduceMotion {
                recentRecords = loadedRecords
            } else {
                withAnimation(ConversionMotion.contentUpdate) {
                    recentRecords = loadedRecords
                }
            }
        }
    }
}

private enum ConversionMotion {
    static let entranceDuration: TimeInterval = 0.38
    static let entranceOffset: CGFloat = 18
    static let entranceScale: CGFloat = 0.985
    static let staggerDelay: TimeInterval = 0.045
    static let pressedScale: CGFloat = 0.985

    static var entrance: Animation {
        .smooth(
            duration: entranceDuration,
            extraBounce: 0
        )
    }

    static var interaction: Animation {
        .snappy(
            duration: 0.18,
            extraBounce: 0
        )
    }

    static var contentUpdate: Animation {
        .smooth(
            duration: 0.24,
            extraBounce: 0
        )
    }
}

private enum ConversionHomeKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case image
    case video
    case audio

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .image:
            L10n.string("conversion.home.image.title")
        case .video:
            L10n.string("conversion.home.video.title")
        case .audio:
            L10n.string("conversion.home.audio.title")
        }
    }

    var detail: String {
        switch self {
        case .image:
            L10n.string("conversion.home.image.tagline")
        case .video:
            L10n.string("conversion.home.video.tagline")
        case .audio:
            L10n.string("conversion.home.audio.tagline")
        }
    }

    var symbol: String {
        switch self {
        case .image:
            "photo.on.rectangle.angled"
        case .video:
            "film.stack"
        case .audio:
            "waveform"
        }
    }

    var formats: [String] {
        switch self {
        case .image:
            ImageConversionEngine.supportedOutputFormats
                .prefix(4)
                .map { $0.rawValue.uppercased() }
        case .video:
            ["MP4", "MOV", "M4V", "HEVC"]
        case .audio:
            ["M4A", "AAC", "WAV", "AIFF"]
        }
    }

    var warmColors: [Color] {
        switch self {
        case .image:
            [
                Color(red: 0.80, green: 0.62, blue: 0.38),
                Color(red: 0.62, green: 0.45, blue: 0.28)
            ]
        case .video:
            [
                Color(red: 0.77, green: 0.45, blue: 0.32),
                Color(red: 0.59, green: 0.32, blue: 0.22)
            ]
        case .audio:
            [
                Color(red: 0.42, green: 0.56, blue: 0.50),
                Color(red: 0.28, green: 0.41, blue: 0.36)
            ]
        }
    }

    var warmGradient: LinearGradient {
        LinearGradient(
            colors: warmColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var warmShadow: Color {
        warmColors[1].opacity(0.32)
    }

    var mediaKind: ConversionMediaKind {
        switch self {
        case .image:
            .image
        case .video:
            .video
        case .audio:
            .audio
        }
    }
}

private struct ConversionHomeRecord: Sendable {
    let completedAt: Date
    let completedCount: Int
}

private actor ConversionHomeHistoryLoader {
    static let shared = ConversionHomeHistoryLoader()

    func load() async -> [ConversionHomeKind: ConversionHomeRecord] {
        var result: [ConversionHomeKind: ConversionHomeRecord] = [:]

        for kind in ConversionHomeKind.allCases {
            let records = await ConversionWorkspace.shared.load(kind.mediaKind)

            let completed = records.compactMap { record -> (URL, Date)? in
                guard record.status == .completed else { return nil }
                guard let outputPath = record.outputPath else { return nil }

                let outputURL = URL(fileURLWithPath: outputPath)

                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    return nil
                }

                let values = try? outputURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                )

                return (
                    outputURL,
                    values?.contentModificationDate ?? .distantPast
                )
            }

            guard let latest = completed.max(by: { $0.1 < $1.1 }) else {
                continue
            }

            result[kind] = ConversionHomeRecord(
                completedAt: latest.1,
                completedCount: completed.count
            )
        }

        return result
    }
}

private struct ConversionHomeCard: View {
    @Environment(\.conversionTheme) private var theme
    let kind: ConversionHomeKind
    let recentRecord: ConversionHomeRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        kind.warmGradient,
                        in: RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )
                    .shadow(
                        color: kind.warmShadow,
                        radius: 6,
                        x: 0,
                        y: 3
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)

                    Text(kind.detail)
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(
                        theme.textSecondary.opacity(0.62)
                    )
            }

            HStack(spacing: 7) {
                ForEach(kind.formats, id: \.self) { format in
                    Text(format)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            theme.cardElevated,
                            in: Capsule()
                        )
                }
            }

            if let recentRecord {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle()
                        .fill(
                            theme.textPrimary.opacity(0.08)
                        )
                        .frame(height: 1)

                    Label(
                        L10n.format(
                            "conversion.home.history.summary",
                            recentRecord.completedAt.formatted(
                                .relative(presentation: .named)
                            ),
                            recentRecord.completedCount
                        ),
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .fill(theme.cardSurface)
            .shadow(
                color: .black.opacity(0.05),
                radius: 12,
                x: 0,
                y: 5
            )
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }
}

private struct ConversionHomeCardButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed && !reduceMotion
                    ? ConversionMotion.pressedScale
                    : 1
            )
            .animation(
                reduceMotion
                    ? nil
                    : ConversionMotion.interaction,
                value: configuration.isPressed
            )
    }
}

private struct ConversionHomeStaggeredAppear: ViewModifier {
    let isVisible: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(
                isVisible || reduceMotion
                    ? 1
                    : 0
            )
            .scaleEffect(
                isVisible || reduceMotion
                    ? 1
                    : ConversionMotion.entranceScale
            )
            .offset(
                y: isVisible || reduceMotion
                    ? 0
                    : ConversionMotion.entranceOffset
            )
            .animation(
                reduceMotion
                    ? nil
                    : ConversionMotion.entrance.delay(
                        Double(index) * ConversionMotion.staggerDelay
                    ),
                value: isVisible
            )
    }
}

private struct ConversionToolDestination: View {
    @Environment(\.conversionTheme) private var theme
    let kind: ConversionHomeKind
    let imageViewModel: ImageConversionViewModel
    let videoViewModel: VideoConversionViewModel
    let audioViewModel: AudioConversionViewModel
    let imageImportSession: ConversionImportSession
    let videoImportSession: ConversionImportSession
    let audioImportSession: ConversionImportSession

    var body: some View {
        Group {
            switch kind {
            case .image:
                ImageConversionContentView(
                    viewModel: imageViewModel,
                    importSession: imageImportSession
                )
            case .video:
                VideoConversionView(
                    viewModel: videoViewModel,
                    importSession: videoImportSession
                )
            case .audio:
                AudioConversionView(
                    viewModel: audioViewModel,
                    importSession: audioImportSession
                )
            }
        }
        .background(converterBackground)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var converterBackground: some View {
        switch theme.background {
        case let .solid(color):
            color.ignoresSafeArea()
        case let .linearGradient(colors, startPoint, endPoint):
            LinearGradient(
                colors: colors,
                startPoint: startPoint,
                endPoint: endPoint
            )
            .ignoresSafeArea()
        }
    }
}

private extension View {
    @ViewBuilder
    func conversionMatchedTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        enabled: Bool
    ) -> some View {
        if #available(iOS 18.0, *) {
            if enabled {
                self.matchedTransitionSource(
                    id: id,
                    in: namespace
                )
            } else {
                self
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func conversionNavigationTransition<ID: Hashable>(
        sourceID: ID,
        in namespace: Namespace.ID,
        enabled: Bool
    ) -> some View {
        if #available(iOS 18.0, *) {
            if enabled {
                self.navigationTransition(
                    .zoom(
                        sourceID: sourceID,
                        in: namespace
                    )
                )
            } else {
                self
            }
        } else {
            self
        }
    }
}
