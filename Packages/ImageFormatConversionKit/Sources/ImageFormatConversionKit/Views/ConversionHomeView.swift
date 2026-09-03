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
    private let animationsEnabled: Bool
    @State private var recentRecords: [ConversionHomeKind: ConversionHomeRecord] = [:]
    @State private var imageViewModel: ImageConversionViewModel
    @State private var videoViewModel: VideoConversionViewModel
    @State private var audioViewModel: AudioConversionViewModel
    @State private var imageImportSession: ConversionImportSession
    @State private var videoImportSession: ConversionImportSession
    @State private var audioImportSession: ConversionImportSession
    @State private var navigationPath: [ConversionHomeKind]
    @State private var isHomeContentVisible = false
    @State private var isGuidePresented: Bool
    @State private var entranceGeneration = 0
    @State private var hasAppeared = false
    @Namespace private var navigationTransitionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        theme: ConversionTheme = .system,
        isTabActive: Bool = true,
        animationsEnabled: Bool = true
    ) {
        self.theme = theme
        self.isTabActive = isTabActive
        self.animationsEnabled = animationsEnabled
        _imageViewModel = State(initialValue: ImageConversionViewModel())
        _videoViewModel = State(initialValue: VideoConversionViewModel())
        _audioViewModel = State(initialValue: AudioConversionViewModel())
        _imageImportSession = State(initialValue: ConversionImportSession())
        _videoImportSession = State(initialValue: ConversionImportSession())
        _audioImportSession = State(initialValue: ConversionImportSession())
        _navigationPath = State(initialValue: Self.initialNavigationPath())
        _isGuidePresented = State(initialValue: Self.shouldPresentGuideOnLaunch())
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                Text(L10n.string("converter.heading"))
                    .appTypeface(.largeTitle.bold(), size: 34, relativeTo: .largeTitle, weight: .bold)
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
                                    enabled: animationsEnabled && !reduceMotion
                                )
                            }
                            .buttonStyle(
                                ConversionHomeCardButtonStyle(
                                    reduceMotion: reduceMotion || !animationsEnabled
                                )
                            )
                            .accessibilityIdentifier("conversion.home.\(kind.rawValue)")
                            .modifier(
                                ConversionHomeStaggeredAppear(
                                    isVisible: isHomeContentVisible,
                                    index: index,
                                    reduceMotion: reduceMotion || !animationsEnabled
                                )
                            )
                        }

                        Label(
                            L10n.string("import.subtitle"),
                            systemImage: "lock.shield"
                        )
                        .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                        .modifier(
                            ConversionHomeStaggeredAppear(
                                isVisible: isHomeContentVisible,
                                index: ConversionHomeKind.allCases.count,
                                reduceMotion: reduceMotion || !animationsEnabled
                            )
                        )
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 24)
                }
                .converterSoftScrollEdge()
            }
            .background(converterBackground)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isGuidePresented = true
                    } label: {
                        Image(systemName: "lightbulb.max.fill")
                    }
                    .accessibilityLabel(L10n.string("conversion.guide.button"))
                    .accessibilityIdentifier("conversion.guide.button")
                }
            }
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
                    enabled: animationsEnabled && !reduceMotion
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
        .sheet(isPresented: $isGuidePresented) {
            ConversionGuideView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .environment(\.conversionTheme, theme)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
    }

    @ViewBuilder
    private var converterBackground: some View {
        ConversionBackgroundView(background: theme.background)
            .ignoresSafeArea()
    }

    private func playEntrance() {
        guard isTabActive else { return }
        entranceGeneration &+= 1
        let generation = entranceGeneration
        resetEntranceWithoutAnimation()

        guard animationsEnabled, !reduceMotion else {
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

            if reduceMotion || !animationsEnabled {
                recentRecords = loadedRecords
            } else {
                withAnimation(ConversionMotion.contentUpdate) {
                    recentRecords = loadedRecords
                }
            }
        }
    }

    /// 提供只在 Debug 构建中生效的确定性截图入口，避免截图流程依赖坐标点击。
    private static func initialNavigationPath() -> [ConversionHomeKind] {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--conversion-guide-screenshot") else {
            return []
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return [] }
        guard let kind = ConversionHomeKind(rawValue: arguments[valueIndex]) else { return [] }
        return [kind]
#else
        return []
#endif
    }

    private static func shouldPresentGuideOnLaunch() -> Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--conversion-guide-screenshot") else {
            return false
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return false }
        let value = arguments[valueIndex]
        return value == "guide" || value.hasPrefix("guide-")
#else
        return false
#endif
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
    let sourceBytes: Int64?
    let outputBytes: Int64?
}

private actor ConversionHomeHistoryLoader {
    static let shared = ConversionHomeHistoryLoader()

    func load() async -> [ConversionHomeKind: ConversionHomeRecord] {
        var result: [ConversionHomeKind: ConversionHomeRecord] = [:]

        for kind in ConversionHomeKind.allCases {
            let records = await ConversionWorkspace.shared.load(kind.mediaKind)

            let completed = records.compactMap { record -> (Date, Int64?, Int64?)? in
                guard record.status == .completed else { return nil }
                guard let outputPath = record.outputPath else { return nil }

                let outputURL = URL(fileURLWithPath: outputPath)

                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    return nil
                }

                let values = try? outputURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                )

                return (
                    values?.contentModificationDate ?? .distantPast,
                    record.sourceBytes > 0 ? record.sourceBytes : nil,
                    values?.fileSize.map(Int64.init).flatMap { $0 > 0 ? $0 : nil }
                )
            }

            guard let latest = completed.max(by: { $0.0 < $1.0 }) else {
                continue
            }

            let hasCompleteSizeHistory = completed.allSatisfy { $0.1 != nil && $0.2 != nil }

            result[kind] = ConversionHomeRecord(
                completedAt: latest.0,
                completedCount: completed.count,
                sourceBytes: hasCompleteSizeHistory
                    ? completed.compactMap(\.1).reduce(0, +)
                    : nil,
                outputBytes: hasCompleteSizeHistory
                    ? completed.compactMap(\.2).reduce(0, +)
                    : nil
            )
        }

        return result
    }
}

private struct ConversionHomeInsetSurface: ViewModifier {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), theme.liquidGlassCardsEnabled && !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(theme.cardElevated, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

private struct ConversionHomeCard: View {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let kind: ConversionHomeKind
    let recentRecord: ConversionHomeRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol)
                    .appTypeface(.system(size: 23, weight: .medium), size: 23, relativeTo: .body, weight: .medium)
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 54, height: 54)
                    .modifier(ConversionHomeInsetSurface(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .appTypeface(.title3.weight(.semibold), size: 20, relativeTo: .title3, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)

                    Text(kind.detail)
                        .appTypeface(.footnote, size: 13, relativeTo: .footnote, weight: .regular)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .appTypeface(.footnote.weight(.semibold), size: 13, relativeTo: .footnote, weight: .semibold)
                    .foregroundStyle(
                        theme.textSecondary.opacity(0.62)
                    )
            }

            HStack(spacing: 7) {
                ForEach(kind.formats, id: \.self) { format in
                    Text(format)
                        .appTypeface(.caption2.weight(.semibold), size: 11, relativeTo: .caption2, weight: .semibold)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .modifier(ConversionHomeInsetSurface(cornerRadius: 100))
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
                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                    .foregroundStyle(theme.textSecondary)

                    if let sizeComparison = sizeComparison(for: recentRecord) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sizeComparison.values)
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(theme.textPrimary)
                            Text(sizeComparison.change)
                                .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .converterCard(cornerRadius: 24)
        .shadow(
            color: usesGlassCard ? .clear : .black.opacity(0.05),
            radius: 12,
            x: 0,
            y: 5
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }

    private var usesGlassCard: Bool {
        theme.liquidGlassCardsEnabled && !reduceTransparency
    }

    /// 将历史输入与真实输出文件体积转换为不暗示释放空间的中性反馈。
    private func sizeComparison(for record: ConversionHomeRecord) -> (values: String, change: String)? {
        guard let sourceBytes = record.sourceBytes, let outputBytes = record.outputBytes else { return nil }
        let source = ByteCountFormatter.string(fromByteCount: sourceBytes, countStyle: .file)
        let output = ByteCountFormatter.string(fromByteCount: outputBytes, countStyle: .file)
        let values = L10n.format("conversion.home.history.size_comparison", source, output)

        if outputBytes < sourceBytes {
            let difference = ByteCountFormatter.string(
                fromByteCount: sourceBytes - outputBytes,
                countStyle: .file
            )
            return (values, L10n.format("conversion.home.history.smaller", difference))
        }
        if outputBytes > sourceBytes {
            let difference = ByteCountFormatter.string(
                fromByteCount: outputBytes - sourceBytes,
                countStyle: .file
            )
            return (values, L10n.format("conversion.home.history.larger", difference))
        }
        return (values, L10n.string("conversion.home.history.unchanged"))
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
        ConversionBackgroundView(background: theme.background)
            .ignoresSafeArea()
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
