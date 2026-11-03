// 转换功能首页及工具导航协调。
// 管理图片、视频、音频入口、快捷压缩请求、分享导入和最近结果展示。
// 快捷入口只导航到对应工具；原件替换需另行审阅和确认。
// 首页持有各工具状态和导入会话，并将快捷请求或分享批次路由到相应页面。
// 最近结果来自工作区摘要；替换审阅、确认和后续清理是独立步骤。

//
//  ConversionHomeView.swift
//
//  文件职责：声明 ConversionHome 界面结构、交互入口与展示状态。
//  所属模块：ImageFormatConversionKit.
//

import SwiftUI

/// 标识一次快捷压缩导航请求，供首页避免重复处理同一请求。
public struct QuickCompressionRequest: Identifiable, Equatable {
    public let id = UUID()
    public let category: ConversionUsageCategory

    /// 按功能分类创建快捷压缩请求，并生成唯一标识用于去重。
    public init(category: ConversionUsageCategory) { self.category = category }
}

/// 协调转换工具导航、分享文件导入、快捷入口和原件替换审阅。
@MainActor
public struct ConversionHomeView: View {
    private let closeButtonTitle: String
    private let onClose: (() -> Void)?
    private let theme: ConversionTheme
    private let isTabActive: Bool
    private let animationsEnabled: Bool
    private let onDetailVisibilityChanged: (Bool) -> Void
    private let quickCompressionRequest: QuickCompressionRequest?
    @State private var handledQuickRequestID: UUID?
    @State private var isQuickCompression = false
    private let shareImport: ShareImportRequest?
    private let onShareImportComplete: (UUID, Set<UUID>) -> Void
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
    @State private var isReplacementReviewPresented = false
    @State private var isReplacementUnavailablePresented = false
    @State private var entranceGeneration = 0
    @State private var hasAppeared = false
    @State private var handledShareRequestID: UUID?
    @Namespace private var navigationTransitionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.conversionUsagePolicy) private var usagePolicy
    @State private var lockedCategory: ConversionUsageCategory?

    /// 保存主页依赖及由调用方提供的操作回调。
    public init(
        theme: ConversionTheme = .system,
        isTabActive: Bool = true,
        animationsEnabled: Bool = true,
        onDetailVisibilityChanged: @escaping (Bool) -> Void = { _ in },
        quickCompressionRequest: QuickCompressionRequest? = nil,
        shareImport: ShareImportRequest? = nil,
        onShareImportComplete: @escaping (UUID, Set<UUID>) -> Void = { _, _ in },
        closeButtonTitle: String = "Close",
        onClose: (() -> Void)? = nil
    ) {
        self.closeButtonTitle = closeButtonTitle
        self.onClose = onClose
        self.theme = theme
        self.isTabActive = isTabActive
        self.animationsEnabled = animationsEnabled
        self.onDetailVisibilityChanged = onDetailVisibilityChanged
        self.quickCompressionRequest = quickCompressionRequest
        self.shareImport = shareImport
        self.onShareImportComplete = onShareImportComplete
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
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(
                            Array(ConversionHomeKind.allCases.enumerated()),
                            id: \.element
                        ) { index, kind in
                            Button {
                                isQuickCompression = false
                                if usagePolicy.allows(kind.usageCategory) {
                                    navigationPath.append(kind)
                                } else {
                                    lockedCategory = kind.usageCategory
                                }
                            } label: {
                                ConversionHomeCard(
                                    kind: kind,
                                    recentRecord: recentRecords[kind],
                                    minimumHeight: min(200, max(130, (min(geometry.size.width, 700) - 8) / 8))
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
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                .converterSoftScrollEdge()
                }
            }
            .background(converterBackground)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onClose) { Image(systemName: "xmark") }
                            .accessibilityLabel(closeButtonTitle)
                            .accessibilityIdentifier("conversion.close")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isGuidePresented = true
                    } label: {
                        Image(systemName: "lightbulb.max.fill")
                            .foregroundStyle(theme.accent)
                    }
                    .accessibilityLabel(L10n.string("conversion.guide.button"))
                    .accessibilityIdentifier("conversion.guide.button")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if replaceableOriginalCount > 0 {
                            isReplacementReviewPresented = true
                        } else {
                            isReplacementUnavailablePresented = true
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(theme.accent)
                    }
                    .accessibilityLabel(L10n.string("conversion.replace.button"))
                    .accessibilityIdentifier("conversion.replace.button")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ConversionHomeKind.self) { kind in
                if usagePolicy.allows(kind.usageCategory) {
                    ConversionToolDestination(
                        kind: kind,
                        isQuickCompression: isQuickCompression,
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
                } else {
                    usagePolicy.upgradeContent(kind.usageCategory)
                }
            }
            .onAppear {
                onDetailVisibilityChanged(!navigationPath.isEmpty)
                if !hasAppeared {
                    hasAppeared = true
                    if isTabActive {
                        playEntrance()
                    }
                }
                loadRecentRecords()
                receiveSharedFilesIfNeeded()
                receiveQuickCompressionIfNeeded()
            }
            .onChange(of: isTabActive) { _, isActive in
                if isActive {
                    playEntrance()
                    receiveSharedFilesIfNeeded()
                    receiveQuickCompressionIfNeeded()
                } else {
                    cancelAndResetEntrance()
                }
            }
            .onChange(of: navigationPath) { _, newPath in
                onDetailVisibilityChanged(!newPath.isEmpty)
            }
            .onChange(of: quickCompressionRequest?.id) { _, _ in
                receiveQuickCompressionIfNeeded()
            }
            .onChange(of: shareImport?.id) { _, _ in
                receiveSharedFilesIfNeeded()
                receiveQuickCompressionIfNeeded()
            }
        }
        .sheet(item: $lockedCategory) { category in
            usagePolicy.upgradeContent(category)
        }
        .onChange(of: usagePolicy.allows(.images)) { _, allowed in
            if allowed { receiveSharedFilesIfNeeded(); receiveQuickCompressionIfNeeded() }
        }
        .sheet(isPresented: $isGuidePresented) {
            ConversionGuideView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isReplacementReviewPresented) {
            ConversionReplacementReviewView(candidates: replacementCandidates) { selected in
                let replacedIDs = try await ConversionOriginalReplacementService.replace(selected)
                let imagesCleaned = await imageViewModel.finishReplacement(replacedIDs)
                let videosCleaned = await videoViewModel.finishReplacement(replacedIDs)
                loadRecentRecords()
                return imagesCleaned && videosCleaned
            }
            .environment(\.conversionTheme, theme)
        }
        .alert(
            L10n.string("conversion.replace.button"),
            isPresented: $isReplacementUnavailablePresented
        ) {
            Button(L10n.string("action.done")) {}
        } message: {
            Text(L10n.string("conversion.replace.unavailable"))
        }
        .environment(\.conversionTheme, theme)
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
    }

    /// 仅在标签激活且请求未处理时导航到对应工具；打开入口不会自动启动转换。
    private func receiveQuickCompressionIfNeeded() {
        guard isTabActive, let request = quickCompressionRequest,
              request.id != handledQuickRequestID else { return }
        let kind: ConversionHomeKind = request.category == .video ? .video : .image
        // Opening a shortcut does not start a batch or change professional settings.
        handledQuickRequestID = request.id
        isQuickCompression = true
        navigationPath = [kind]
    }

    /// 检查对应功能权限后导入分享批次，并仅向调用方回报实际成功暂存的条目。
    private func receiveSharedFilesIfNeeded() {
        guard isTabActive, let request = shareImport,
              handledShareRequestID != request.id else { return }
        let category: ConversionUsageCategory = request.kind == .image ? .images : .video
        guard usagePolicy.allows(category) else {
            lockedCategory = category
            return
        }
        isQuickCompression = false
        handledShareRequestID = request.id
        navigationPath = [request.kind == .image ? .image : .video]
        Task {
            let urls = request.files.map(\.url)
            let importedURLs = if request.kind == .image {
                await imageViewModel.addFiles(urls)
            } else {
                await videoViewModel.addFiles(urls)
            }
            let importedIDs = Set(request.files.compactMap { file in
                importedURLs.contains(file.url.standardizedFileURL) ? file.id : nil
            })
            onShareImportComplete(request.batchID, importedIDs)
        }
    }

    private var replaceableOriginalCount: Int {
        replacementCandidates.count
    }

    private var replacementCandidates: [ConversionReplacementCandidate] {
        imageViewModel.replacementCandidates + videoViewModel.replacementCandidates
    }

    @ViewBuilder
    private var converterBackground: some View {
        ConversionBackgroundView(background: theme.background)
            .ignoresSafeArea()
    }

    /// 按标签激活状态和动态效果设置安排首页入场，并通过代次忽略失效任务。
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

    /// 递增代次使待执行的入场任务失效，并重置展示状态。
    private func cancelAndResetEntrance() {
        entranceGeneration &+= 1
        resetEntranceWithoutAnimation()
    }

    /// 关闭动画并重置入场状态，供重新展示时恢复初始布局。
    private func resetEntranceWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isHomeContentVisible = false
        }
    }

    /// 异步读取最近结果；根据动态效果偏好更新首页展示。
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

    /// 根据已有的启动标记判断是否展示转换指南。
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

/// Displays the production conversion card with sample-free, local-only content.
public struct ConversionIntroductionPreview: View {
    private let theme: ConversionTheme
    private let step: Int

    /// 使用指定主题和步骤构造主页展示入口。
    public init(theme: ConversionTheme, step: Int) {
        self.theme = theme
        self.step = step
    }

    public var body: some View {
        ConversionHomeCard(
            kind: ConversionHomeKind.allCases[
                min(max(step, 0), ConversionHomeKind.allCases.count - 1)
            ],
            recentRecord: nil
        )
        .environment(\.conversionTheme, theme)
    }
}

/// 集中定义转换主页使用的动效参数。
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

/// 标识主页展示的各类转换工具及其展示信息。
private enum ConversionHomeKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case video
    case image
    case audio

    var id: Self {
        self
    }

    var usageCategory: ConversionUsageCategory {
        switch self {
        case .image: .images
        case .video: .video
        case .audio: .audio
        }
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
                .map(\.displayName)
        case .video:
            VideoOutputContainer.allCases.map { $0.rawValue.uppercased() }
        case .audio:
            ["MP3", "AAC", "WAV", "AIFF"]
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

/// 保存转换主页卡片所需的记录摘要。
private struct ConversionHomeRecord: Sendable {
    let completedAt: Date
    let completedCount: Int
    let sourceBytes: Int64?
    let outputBytes: Int64?
}

/// 加载转换工作区历史，为首页生成各工具的最近结果摘要。
private actor ConversionHomeHistoryLoader {
    static let shared = ConversionHomeHistoryLoader()

    /// 只统计输出文件仍存在的完成项；缺少任一大小记录时不展示总大小对比。
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

/// 为主页内容提供内凹表面样式。
private struct ConversionHomeInsetSurface: ViewModifier {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    /// 将内凹表面样式应用于主页内容。
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), theme.liquidGlassCardsEnabled && !reduceTransparency {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(theme.cardElevated, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

/// 展示单个转换工具的摘要、状态和操作入口。
private struct ConversionHomeCard: View {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let kind: ConversionHomeKind
    let recentRecord: ConversionHomeRecord?
    var minimumHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol)
                    .appTypeface(.system(size: 23, weight: .medium), size: 23, relativeTo: .body, weight: .medium)
                    .foregroundStyle(theme.accent)
                    .frame(width: 54, height: 54)
                    .modifier(ConversionHomeInsetSurface(cornerRadius: 16))

                Text(kind.title)
                    .appTypeface(.title3.weight(.semibold), size: 20, relativeTo: .title3, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .appTypeface(.footnote.weight(.semibold), size: 13, relativeTo: .footnote, weight: .semibold)
                    .foregroundStyle(theme.accent.opacity(0.72))
            }

            HStack(spacing: 7) {
                ForEach(kind.formats, id: \.self) { format in
                    Text(format)
                        .appTypeface(.caption2.weight(.semibold), size: 11, relativeTo: .caption2, weight: .semibold)
                        .foregroundStyle(theme.accent)
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
            minHeight: minimumHeight,
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

/// 定义主页卡片的按压反馈。
private struct ConversionHomeCardButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    /// 根据按钮按压状态调整卡片外观。
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

/// 为主页项目提供按顺序出现的展示效果。
private struct ConversionHomeStaggeredAppear: ViewModifier {
    let isVisible: Bool
    let index: Int
    let reduceMotion: Bool

    /// 将内凹表面样式应用于主页内容。
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

/// 根据选中的工具展示相应转换页面。
private struct ConversionToolDestination: View {
    @Environment(\.conversionTheme) private var theme
    let kind: ConversionHomeKind
    let isQuickCompression: Bool
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
                    importSession: imageImportSession,
                    isQuickCompression: isQuickCompression
                )
            case .video:
                VideoConversionView(
                    viewModel: videoViewModel,
                    importSession: videoImportSession,
                    isQuickCompression: isQuickCompression
                )
            case .audio:
                AudioConversionView(
                    viewModel: audioViewModel,
                    importSession: audioImportSession
                )
            }
        }
        .background(converterBackground)
        .navigationTitle(isQuickCompression ? L10n.string(kind == .video ? "quick.video" : "quick.image") : kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var converterBackground: some View {
        ConversionBackgroundView(background: theme.background)
            .ignoresSafeArea()
    }
}

/// 封装不同系统版本下的主页导航转场适配。
private extension View {
    @ViewBuilder
    /// 在系统支持时标记导航转场的来源视图。
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
    /// 在系统支持时应用与来源视图对应的导航转场。
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
