// 照片首页、容量概览和分类详情。
// 根据授权、分析与删除状态展示内容；媒体数据与实际操作由相册状态对象提供。
// 首页将相册授权、容量和分类结果连接到快速清理、压缩、预览与审阅入口。
// 详情视图维护当前选择，并通过相册模型提交用户确认的操作；部分分析结果可单独展示。

//
//  PhotosView.swift
//  CleanMyIPhone
//


import Photos
import ImageFormatConversionKit
import SwiftUI
//import UIKit

/// 照片首页根据授权、资源分析和容量状态展示概览及分类入口。
struct PhotosView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var accessStore: PremiumFeatureAccessStore
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let isTabActive: Bool
    var onOpenStorage: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onOpenConversion: () -> Void = {}
    @State private var animatedStorageFraction = 0.0
    @State private var showsQuickClean = false
    @State private var swipeReviewRequest: SwipeReviewRequest?

    /// 冻结一次审阅所需的资源清单及建议删除集合。
    private struct SwipeReviewRequest: Identifiable {
        let id = UUID()
        let assetIDs: [String]
        let suggestedDeletionIDs: Set<String>
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Group {
                    switch viewModel.authorizationStatus {
                    case .notDetermined:
                        permissionView(
                            title: "Access your photos",
                            message: "Continue to choose which photos and videos Filevra can display, analyze, and help you organize.",
                            buttonTitle: "Continue",
                            action: viewModel.requestAccess
                        )
                    case .authorized:
                        mediaContent
                    case .limited:
                        limitedPhotoContent
                    case .denied:
                        permissionView(
                            title: "Photo access is off",
                            message: "Enable Photos access in Settings to display your images.",
                            buttonTitle: "Open Settings",
                            action: viewModel.openSettings
                        )
                    case .restricted:
                        permissionView(
                            title: "Photo access is restricted",
                            message: "This device currently prevents the app from accessing Photos.",
                            buttonTitle: nil,
                            action: {}
                        )
                    @unknown default:
                        permissionView(
                            title: "Photo access is unavailable",
                            message: "The current Photos authorization state is not supported.",
                            buttonTitle: nil,
                            action: {}
                        )
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showsQuickClean = true } label: {
                            Label("Quick Cleanup", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("media.quickClean.open")
                        Button(action: openAllPhotosSwipeReview) {
                            Label("Swipe Review", systemImage: "rectangle.stack")
                        }
                        .disabled(!viewModel.assets.contains { $0.mediaType == .image })
                        .accessibilityIdentifier("media.swipeReview.open")
                        Button(action: onOpenStorage) {
                            Label("Storage", systemImage: "externaldrive")
                        }
                        .accessibilityIdentifier("media.storage")
                        Button(action: onOpenConversion) {
                            Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityIdentifier("media.convert")
                    } label: {
                        Label("media.more", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("media.more")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("media.settings")
                }
            }
            .navigationDestination(isPresented: $showsQuickClean) {
                MediaQuickCleanView(photoLibrary: viewModel, accessStore: accessStore)
            }
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $swipeReviewRequest) { request in
            MediaSwipeReviewView(
                assetIDs: request.assetIDs,
                protectedAssetIDs: [],
                suggestedDeletionIDs: request.suggestedDeletionIDs,
                photoLibrary: viewModel,
                onDismiss: { swipeReviewRequest = nil }
            )
        }
        .onAppear {
            animateStorageBarIfNeeded()
        }
        .onChange(of: isTabActive) { _, isActive in
            if isActive {
                animateStorageBarIfNeeded()
            } else {
                animatedStorageFraction = 0
            }
        }
        .onChange(of: viewModel.storageSnapshot) { _, _ in
            animateStorageBarIfNeeded()
        }
        .onChange(of: themeSettings.interfaceAnimationsEnabled) { _, _ in
            animateStorageBarIfNeeded()
        }
    }

    /// 收集当前照片标识和可用建议，在进入时固定本次审阅清单。
    private func openAllPhotosSwipeReview() {
        // Freeze the review inventory once at entry, rather than rebuilding it for each swipe.
        let identifiers = viewModel.assets.compactMap { asset in
            asset.mediaType == .image ? asset.localIdentifier : nil
        }
        guard !identifiers.isEmpty else { return }
        let suggestions: Set<String>
        switch viewModel.analysisState {
        case .success(let result), .partialFailure(let result):
            suggestions = result.suggestedCleanupIDs
        default:
            suggestions = []
        }
        swipeReviewRequest = SwipeReviewRequest(assetIDs: identifiers, suggestedDeletionIDs: suggestions)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if viewModel.isLoading {
            mediaDashboard
        } else if viewModel.assets.isEmpty {
            ScrollView {
                VStack(spacing: 24) {
                    ContentUnavailableView(
                        "No Media",
                        systemImage: "photo.on.rectangle",
                        description: Text("No photos or videos are available in your library.")
                    )
                    quickCompressionCards
                }
                .padding(16)
            }
        } else {
            mediaDashboard
        }
    }

    @ViewBuilder
    private var limitedPhotoContent: some View {
        VStack(spacing: 12) {
            Label("Limited Photo Access", systemImage: "photo.badge.checkmark")
                .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)

            Text("Only the photos you selected are available to Filevra.")
                .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Manage Selected Photos") {
                viewModel.presentLimitedLibraryPicker()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentPrimary)

            mediaContent
        }
        .padding(.horizontal)
    }

    private var mediaTitle: some View {
        Text("My Space")
            .appTypeface(.largeTitle.bold(), size: 34, relativeTo: .largeTitle, weight: .bold)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var mediaDashboard: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let windowHeight = frame.maxY + geometry.safeAreaInsets.bottom
            let topInset = max(4, (windowHeight * 0.19 - frame.minY) / 2)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 24) {
                    VStack(spacing: 12) {
                        mediaTitle
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                        storageOverview
                    }
                    analysisContent
                    quickCompressionCards
                }
                .padding(.horizontal, 4)
                .padding(.top, topInset)
                .padding(.bottom, 8)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .appSoftScrollEdge()
        }
    }

    @ViewBuilder
    private var analysisContent: some View {
        switch viewModel.analysisState {
        case .idle:
            VStack(alignment: .leading, spacing: 14) {
                Label("cleanup.scan.title", systemImage: "sparkles")
                    .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)
                Text(viewModel.isLoading
                     ? LocalizedStringKey("Loading media…")
                     : LocalizedStringKey("cleanup.scan.hint"))
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.startAnalysis()
                } label: {
                    Label("cleanup.scan.action", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentPrimary)
                .disabled(viewModel.isLoading)
            }
            .mediaAnalysisCard()

        case .analyzing(let progress):
            VStack(alignment: .leading, spacing: 10) {
                Text(analysisTitle(for: progress.phase))
                    .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                WaveProgressView(
                    progress: progress.fractionCompleted,
                    tint: theme.accentPrimary
                )
                Text("Analyzed \(progress.completed) of \(progress.total)")
                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                    .foregroundStyle(.secondary)
            }
            .mediaAnalysisCard()

        case .success(let result):
            MediaDashboardResultsView(
                result: result,
                isPartial: false,
                viewModel: viewModel
            )

        case .partialFailure(let result):
            MediaDashboardResultsView(
                result: result,
                isPartial: true,
                viewModel: viewModel
            )

        case .empty:
            Label("No media is available to analyze.", systemImage: "photo.on.rectangle")
                .mediaAnalysisCard()

        case .cancelled:
            VStack(alignment: .leading, spacing: 12) {
                Label("Analysis cancelled. No files were changed.", systemImage: "pause.circle")
                Button("Analyze Again") {
                    viewModel.startAnalysis()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentPrimary)
            }
            .mediaAnalysisCard()

        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(theme.negativeRed)
                .mediaAnalysisCard()
        }
    }

    @ViewBuilder
    private var storageOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result = cleanupResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("cleanup.space.title")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                    Text(sizeText(result.cleanupReviewIDs))
                        .appTypeface(.largeTitle.bold(), size: 34, relativeTo: .largeTitle, weight: .bold)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("media.cleanup.estimate")
                }
            }

            if let storage = viewModel.storageSnapshot {
                MediaStorageOverview(
                    storage: storage,
                    photoBytes: viewModel.estimatedPhotoLibraryBytes,
                    videoBytes: viewModel.estimatedVideoLibraryBytes,
                    animatedUsedFraction: animatedStorageFraction,
                    animationsEnabled: themeSettings.interfaceAnimationsEnabled && !reduceMotion
                )
            }

        }
        .padding(12)
        .appContentCard(cornerRadius: 22)
    }

    private var cleanupResult: MediaClassificationResult? {
        switch viewModel.analysisState {
        case .success(let result), .partialFailure(let result): result
        default: nil
        }
    }

    /// 将指定资源集合的估算大小格式化为文件大小文案。
    private func sizeText(_ ids: Set<String>) -> String {
        ByteCountFormatter.string(fromByteCount: viewModel.estimatedByteCount(for: ids), countStyle: .file)
    }

    private var quickCompressionCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("quick.compress.title")
                .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)
                .padding(.horizontal, 12)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach([MediaCompressionCategory.video, .image]) { category in
                    let assets = category.assets(in: viewModel)
                    NavigationLink {
                        MediaCompressionView(category: category, library: viewModel)
                    } label: {
                        MediaCategoryCard(
                            title: NSLocalizedString(category.titleKey, comment: ""),
                            detail: String.localizedStringWithFormat(AppL10n.string("%lld items"), Int64(assets.count)),
                            representativeAssetID: assets.first?.localIdentifier,
                            systemImage: category.symbol,
                            aspectRatio: 3.0 / 4.0,
                            viewModel: viewModel
                        )
                        .overlay(alignment: .topTrailing) {
                            if !accessStore.allows(category == .video ? .videoCompression : .imageConversion) {
                                Text("Premium").font(.caption.weight(.semibold)).foregroundStyle(.white)
                                    .padding(8).background(.black.opacity(0.5), in: Capsule()).padding(10)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("media.compress." + category.rawValue)
                }
            }
        }
    }

    /// 页面活跃时更新容量条；关闭动画或启用减少动态效果时直接显示最终值。
    private func animateStorageBarIfNeeded() {
        guard isTabActive, let storage = viewModel.storageSnapshot else { return }
        guard themeSettings.interfaceAnimationsEnabled, !reduceMotion else {
            animatedStorageFraction = storage.usedFraction
            return
        }
        animatedStorageFraction = 0

        Task { @MainActor in
            // Yield once so SwiftUI renders the empty track before the fill animation.
            await Task.yield()
            guard isTabActive else { return }
            withAnimation(.spring(duration: 0.72, bounce: 0.16)) {
                animatedStorageFraction = storage.usedFraction
            }
        }
    }

    /// 将当前分析阶段映射为界面进度文案。
    private func analysisTitle(for phase: MediaAnalysisPhase) -> LocalizedStringKey {
        switch phase {
        case .discovering: "Classifying videos…"
        case .generatingFeatures: "Analyzing image features…"
        case .comparingImages: "Grouping similar photos…"
        }
    }

    /// 展示授权状态说明及可选操作按钮。
    private func permissionView(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        buttonTitle: LocalizedStringKey?,
        action: @escaping () -> Void
    ) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    ContentUnavailableView {
                        Label(title, systemImage: "photo.on.rectangle")
                    } description: {
                        Text(message)
                    } actions: {
                        if let buttonTitle {
                            Button(buttonTitle, action: action)
                                .buttonStyle(.borderedProminent)
                                .tint(theme.accentPrimary)
                        }
                    }
                    // File imports do not require access to the Photos library.
                    quickCompressionCards
                }
                .padding(16)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
        }
    }
}

/// 将完整或部分媒体分类结果展示为首页分类入口。
private struct MediaDashboardResultsView: View {
    let result: MediaClassificationResult
    let isPartial: Bool
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: horizontalSizeClass == .regular ? 3 : 2
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(cleanupCategories) { category in
                    categoryLink(category)
                }
            }


            if isPartial {
                Label(
                    "\(result.skippedImageCount) iCloud or unavailable image(s) were skipped.",
                    systemImage: "icloud.slash"
                )
                .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                .foregroundStyle(.secondary)
            }

        }
        .onAppear {
            viewModel.startCachingThumbnails(
                for: Array(previewCacheIDs).prefix(80),
                targetSize: thumbnailTargetSize
            )
        }
        .onDisappear {
            viewModel.cancelExactByteCountRequests()
            viewModel.stopCachingThumbnails(
                for: Array(previewCacheIDs).prefix(80),
                targetSize: thumbnailTargetSize
            )
        }
    }

    private var previewCacheIDs: [String] {
        var seen = Set<String>()
        return (
            result.similarImageIDs.prefix(24)
            + result.videoIDs.prefix(24)
            + result.screenshotIDs.prefix(24)
            + result.livePhotoIDs.prefix(24)
            + viewModel.cityPhotoIDs.prefix(24)
            + viewModel.otherPhotoIDs(excluding: result).prefix(24)
        ).filter { seen.insert($0).inserted }
    }

    private var thumbnailTargetSize: CGSize {
        let pixelWidth = 140 * displayScale
        return CGSize(width: pixelWidth, height: pixelWidth)
    }

    private var cleanupCategories: [MediaCategorySummary] {
        [
            MediaCategorySummary(
                title: AppL10n.string("Similar Photos"),
                assetIDs: result.similarImageIDs,
                systemImage: "photo.stack",
                protectedAssetIDs: Set(result.similarImageGroups.map(\.suggestedKeeperID)),
                suggestedDeletionIDs: Set(result.similarImageGroups.flatMap { group in
                    group.items.map(\.id).filter { $0 != group.suggestedKeeperID }
                })
            ),
            MediaCategorySummary(
                title: AppL10n.string("Videos"),
                assetIDs: result.videoIDs,
                systemImage: "video.fill"
            ),
            MediaCategorySummary(
                title: AppL10n.string("Screenshots"),
                assetIDs: result.screenshotIDs,
                systemImage: "iphone",
                showsDateGroups: true
            ),
            MediaCategorySummary(
                title: AppL10n.string("Live Photos"),
                assetIDs: result.livePhotoIDs,
                systemImage: "livephoto"
            ),
            MediaCategorySummary(title: AppL10n.string("City Photos"), assetIDs: viewModel.cityPhotoIDs, systemImage: "building.2"),
            MediaCategorySummary(title: AppL10n.string("Other Photos"), assetIDs: viewModel.otherPhotoIDs(excluding: result), systemImage: "photo")
        ]
    }

    /// 创建分类详情入口，并传递资源、保护项和建议删除项。
    private func categoryLink(_ category: MediaCategorySummary) -> some View {
        NavigationLink {
            MediaCategoryDetailView(
                title: category.title,
                showsSimilarGroups: !category.protectedAssetIDs.isEmpty,
                showsDateGroups: category.showsDateGroups,
                assetIDs: category.assetIDs,
                protectedAssetIDs: category.showsDateGroups ? [] : result.protectedKeeperIDs,
                suggestedDeletionIDs: category.suggestedDeletionIDs,
                viewModel: viewModel
            )
        } label: {
            MediaCategoryCard(
                title: category.title,
                detail: String.localizedStringWithFormat(
                    AppL10n.string("%lld items"),
                    Int64(category.showsDateGroups ? category.assetIDs.count : category.assetIDs.filter { !result.protectedKeeperIDs.contains($0) }.count)
                ),
                representativeAssetID: category.assetIDs.first,
                systemImage: category.systemImage,
                viewModel: viewModel
            )
        }
        .buttonStyle(.plain)
        .disabled(category.assetIDs.isEmpty)
    }



}

/// 展示设备容量与照片、视频等占用比例。
struct MediaStorageOverview: View {
    @Environment(\.appTheme) private var theme
    let storage: DeviceStorageSnapshot
    let photoBytes: Int64
    let videoBytes: Int64
    let animatedUsedFraction: Double
    let animationsEnabled: Bool

    private var visiblePhotoBytes: Int64 { min(max(photoBytes, 0), storage.usedBytes) }
    private var visibleVideoBytes: Int64 {
        min(max(videoBytes, 0), max(storage.usedBytes - visiblePhotoBytes, 0))
    }
    private var otherUsedBytes: Int64 {
        max(storage.usedBytes - visiblePhotoBytes - visibleVideoBytes, 0)
    }

    private var segments: [MediaStorageSegment] {
        [
            MediaStorageSegment(
                title: AppL10n.string("Photos"),
                bytes: visiblePhotoBytes,
                color: theme.positiveGreen.opacity(0.82)
            ),
            MediaStorageSegment(
                title: AppL10n.string("Videos"),
                bytes: visibleVideoBytes,
                color: theme.fileCategoryColor(.document).opacity(0.82)
            ),
            MediaStorageSegment(
                title: AppL10n.string("System & Apps"),
                bytes: otherUsedBytes,
                color: theme.warningOrange.opacity(0.72)
            ),
            MediaStorageSegment(
                title: AppL10n.string("Available"),
                bytes: storage.availableBytes,
                color: theme.textTertiary.opacity(0.42)
            )
        ]
    }

    private let legendColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                let spacing: CGFloat = 1
                let availableWidth = max(
                    proxy.size.width - spacing * CGFloat(segments.count - 1),
                    0
                )
                let widths = displayWidths(totalWidth: availableWidth)

                HStack(spacing: spacing) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        segment.color
                            .frame(width: widths[index])
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(
                    animationsEnabled ? .spring(duration: 0.72, bounce: 0.16) : nil,
                    value: animatedUsedFraction
                )
            }
            .frame(height: 42)
            .background(
                theme.cardElevated,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 7, height: 7)
                        Text(segment.title)
                            .lineLimit(1)
                        Text(byteCountText(segment.bytes))
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 计算字节数占设备总容量的比例，并限制在零到一之间。
    private func fraction(for bytes: Int64) -> Double {
        guard storage.totalBytes > 0 else { return 0 }
        return min(max(Double(bytes) / Double(storage.totalBytes), 0), 1)
    }

    private var usedAnimationScale: Double {
        guard storage.usedFraction > 0 else { return 0 }
        return min(max(animatedUsedFraction / storage.usedFraction, 0), 1)
    }

    /// 按容量占比和动画进度计算各色段宽度，并保持少量占用可见。
    private func displayWidths(totalWidth: CGFloat) -> [CGFloat] {
        guard totalWidth > 0 else { return Array(repeating: 0, count: segments.count) }

        var widths = segments.enumerated().map { index, segment in
            let animatedFraction: CGFloat = index == segments.count - 1
                ? CGFloat(max(1 - animatedUsedFraction, 0))
                : CGFloat(fraction(for: segment.bytes) * usedAnimationScale)
            let naturalWidth = totalWidth * animatedFraction

            // Preserve truthful proportions while ensuring a non-zero category remains visible.
            guard index != segments.count - 1, segment.bytes > 0 else { return naturalWidth }
            return max(naturalWidth, 6 * CGFloat(usedAnimationScale))
        }

        let overflow = max(widths.reduce(0, +) - totalWidth, 0)
        if overflow > 0,
           let largestIndex = widths.indices.max(by: { widths[$0] < widths[$1] }) {
            widths[largestIndex] = max(widths[largestIndex] - overflow, 0)
        }
        return widths
    }

    /// 按文件大小格式化字节数。
    private func byteCountText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

/// 保存容量图中一段的名称、字节数及颜色。
private struct MediaStorageSegment {
    let title: String
    let bytes: Int64
    let color: Color
}

/// 保存分类展示与审阅需要的资源、保护项和建议删除项。
private struct MediaCategorySummary: Identifiable {
    let showsDateGroups: Bool
    let title: String
    let assetIDs: [String]
    let systemImage: String
    let protectedAssetIDs: Set<String>
    let suggestedDeletionIDs: Set<String>

    /// 创建媒体分类展示数据，并携带审阅时的保护与建议删除集合。
    init(title: String, assetIDs: [String], systemImage: String, showsDateGroups: Bool = false,
         protectedAssetIDs: Set<String> = [], suggestedDeletionIDs: Set<String> = []) {
        self.showsDateGroups = showsDateGroups
        self.title = title
        self.assetIDs = assetIDs
        self.systemImage = systemImage
        self.protectedAssetIDs = protectedAssetIDs
        self.suggestedDeletionIDs = suggestedDeletionIDs
    }

    var id: String { title }
}

/// 展示分类名称、摘要和代表性缩略图。
private struct MediaCategoryCard: View {
    let title: String
    let detail: String?
    let representativeAssetID: String?
    let systemImage: String
    var aspectRatio: CGFloat = 1
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let representativeAssetID {
                    GeometryReader { proxy in
                        MediaAssetThumbnailView(
                            assetID: representativeAssetID,
                            viewModel: viewModel,
                            targetSizeInPoints: proxy.size
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    Image(systemName: systemImage)
                        .appTypeface(.largeTitle, size: 34, relativeTo: .largeTitle, weight: .regular)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let detail {
                        Text(detail)
                            .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(representativeAssetID == nil ? 0.62 : 1)
    }
}

/// 展示单个分类中的媒体，协调选择、预览和删除确认。
private struct MediaCategoryDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityCoordinator
    let title: String
    let showsSimilarGroups: Bool
    let showsDateGroups: Bool
    let assetIDs: [String]
    let protectedAssetIDs: Set<String>
    let suggestedDeletionIDs: Set<String>
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale
    @StateObject private var dateSectionStore = MediaDateSectionStore()
    @State private var didInitializeSelection = false
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var isDeleteConfirmationPresented = false
    @State private var previewAssetID: String?
    @StateObject private var deletionEffectController = MediaDeletionEffectController()

    private var similarGroups: [SimilarImageGroup] {
        guard showsSimilarGroups else { return [] }
        let result: MediaClassificationResult
        switch viewModel.analysisState {
        case .success(let value), .partialFailure(let value): result = value
        default: return []
        }
        return result.similarImageGroups.filter { protectedAssetIDs.contains($0.suggestedKeeperID) }
    }

    private var groupedPhotos: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(similarGroups) { group in
                    let others = group.items.map(\.id).filter {
                        $0 != group.suggestedKeeperID && viewModel.asset(withIdentifier: $0) != nil
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(String.localizedStringWithFormat(AppL10n.string("similar.group.count"), others.count + 1))
                                .appTypeface(.headline, size: 18, relativeTo: .headline, weight: .semibold)
                            Spacer()
                            Button {
                                isSelecting = true
                                let ids = Set(others)
                                if ids.isSubset(of: selectedIDs) { selectedIDs.subtract(ids) }
                                else { selectedIDs.formUnion(ids) }
                            } label: {
                                Image(systemName: !others.isEmpty && Set(others).isSubset(of: selectedIDs) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel(Text("Select All"))
                        }
                        HStack(alignment: .top, spacing: 8) {
                            groupPhoto(group.suggestedKeeperID, keeper: true, height: 280)
                            VStack(spacing: 8) {
                                ForEach(others.prefix(2), id: \.self) { id in
                                    groupPhoto(id, keeper: false, height: others.count == 1 ? 280 : 136)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        // Keep every remaining photo in the page's scroll flow;
                        // nested fixed-height scrolling hides large groups.
                        if others.count > 2 {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(others.dropFirst(2), id: \.self) { id in
                                    groupPhoto(id, keeper: false, height: 136)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .appContentCard()
                }
            }
            .padding(12)
        }
    }

    private var screenshotsByDate: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(dateSections) { section in
                    let selectableIDs = Set(section.assetIDs).subtracting(protectedAssetIDs)
                    let allSelected = !selectableIDs.isEmpty && selectableIDs.isSubset(of: selectedIDs)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.day?.formatted(date: .abbreviated, time: .omitted) ?? AppL10n.string("Unknown Date"))
                                    .appTypeface(.headline, size: 18, relativeTo: .headline, weight: .semibold)
                                Text("\(section.assetIDs.count) items")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                isSelecting = true
                                if allSelected { selectedIDs.subtract(selectableIDs) }
                                else { selectedIDs.formUnion(selectableIDs) }
                            } label: {
                                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel(Text(allSelected ? "Deselect All" : "Select All"))
                            .disabled(selectableIDs.isEmpty)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(section.assetIDs, id: \.self) { id in
                                groupPhoto(id, keeper: protectedAssetIDs.contains(id), height: 160)
                            }
                        }
                    }
                    .padding(12)
                    .appContentCard()
                }
            }
            .padding(12)
        }
    }

    /// 展示相似照片组中的单张资源，标记保留项并允许打开预览。
    private func groupPhoto(_ id: String, keeper: Bool, height: CGFloat) -> some View {
        Button { previewAssetID = id } label: {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    GeometryReader { proxy in
                        MediaAssetThumbnailView(assetID: id, viewModel: viewModel)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomLeading) {
            if keeper {
                Label("similar.keep", systemImage: "checkmark.shield.fill")
                    .appTypeface(.caption.bold(), size: 13, relativeTo: .caption, weight: .bold)
                    .padding(8)
                    .foregroundStyle(.white)
                    .background(theme.accentPrimary, in: Capsule())
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !keeper {
                Button {
                    isSelecting = true
                    if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
                } label: {
                    Image(systemName: selectedIDs.contains(id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(.white, theme.accentPrimary)
                        .padding(10)
                        .background(.black.opacity(0.25), in: Circle())
                }
                .accessibilityLabel(Text("Select"))
                .padding(4)
            }
        }
    }

    private func reconcileSelection() {
        // 即使列表已过滤缺失项，旧选择也可能仍持有它们，必须独立收缩选择集合。
        let availableIDs = Set(visibleAssetIDs)
        selectedIDs.formIntersection(availableIDs.subtracting(protectedAssetIDs))
        isDeleteConfirmationPresented = false
        if let previewAssetID, !availableIDs.contains(previewAssetID) {
            self.previewAssetID = nil
        }
    }

    private var visibleAssetIDs: [String] {
        chronologicallySortedAssetIDs
    }

    private var dateSections: [MediaDateSection] {
        dateSectionStore.sections(assetIDs: assetIDs, libraryRevision: viewModel.mediaAssetRevision) {
            assetIDs.compactMap { assetID in
                guard let asset = viewModel.asset(withIdentifier: assetID) else { return nil }
                return MediaDatedAsset(id: assetID, creationDate: asset.creationDate)
            }
        }
    }

    private var chronologicallySortedAssetIDs: [String] {
        _ = dateSections
        return dateSectionStore.orderedAssetIDs
    }

    private var displayedSections: [MediaDateSection] {
        guard !themeSettings.mediaDateHeadersEnabled else { return dateSections }
        _ = dateSections
        return dateSectionStore.unsectioned
    }

    private var preheatedAssetIDs: ArraySlice<String> {
        chronologicallySortedAssetIDs.prefix(60)
    }

    private var thumbnailTargetSize: CGSize {
        let pixelWidth = 140 * displayScale
        return CGSize(width: pixelWidth, height: pixelWidth)
    }

    var body: some View {
        ZStack {
            // UICollectionView 保持透明，由页面统一承载当前主题的单色、渐变或 Mesh 背景。
            AppBackground()
                .accessibilityHidden(true)

            Group {
                if visibleAssetIDs.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "photo.on.rectangle",
                        description: Text("No media matched this category.")
                    )
                } else if showsDateGroups {
                    screenshotsByDate
                } else if !similarGroups.isEmpty {
                    groupedPhotos
                } else {
                    MediaInteractiveGrid(
                        sections: displayedSections,
                        showsDateHeaders: themeSettings.mediaDateHeadersEnabled,
                        selectedIDs: $selectedIDs,
                        isSelecting: isSelecting,
                        viewModel: viewModel,
                        accentColor: theme.accentPrimary,
                        deletionEffectController: deletionEffectController,
                        onOpen: { previewAssetID = $0 },
                        onBeginSelecting: { assetID in
                            isSelecting = true
                            selectedIDs.insert(assetID)
                        }
                    )
                    .background(Color.clear)
                    // 仅让网格背景延伸到系统栏后方；UICollectionView 仍通过 automatic inset 保持内容可操作。
                    .ignoresSafeArea(.all, edges: .all)
                    // 网格经过顶部导航和底部浮动控件时使用柔和边缘；不改变其他页面的 Automatic 策略。
                    .appSoftScrollEdge()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // The standard grid uses edge selection gestures; similar groups use
        // explicit buttons and must retain native back navigation when selected.
        .navigationBarBackButtonHidden(isSelecting && !showsSimilarGroups && !showsDateGroups)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button(selectedIDs == Set(visibleAssetIDs).subtracting(protectedAssetIDs) ? "Deselect All" : "Select All") {
                        if selectedIDs == Set(visibleAssetIDs).subtracting(protectedAssetIDs) {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(visibleAssetIDs).subtracting(protectedAssetIDs)
                        }
                    }
                    Button("Done") {
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                } else {
                    Button("Select") {
                        isSelecting = true
                    }
                    .disabled(visibleAssetIDs.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if case let .success(deletedCount, estimatedBytes) = viewModel.deletionState {
                    deletionReceipt(
                        deletedCount: deletedCount,
                        estimatedBytes: estimatedBytes
                    )
                }

                if isSelecting {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(selectedIDs.count) selected")
                                .appTypeface(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline, weight: .semibold)
                            Text("Estimated \(selectedMediaSizeText)")
                                .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            if viewModel.deletionState.isDeleting {
                                ProgressView()
                            } else {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .appGlassButtonStyle()
                        .foregroundStyle(theme.negativeRed)
                        .disabled(selectedIDs.isEmpty || viewModel.deletionState.isDeleting)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .alert("Delete selected media?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let ids = selectedIDs
                let effectToken = deletionEffectController.capture(assetIDs: ids)
                Task {
                    let succeeded = await viewModel.deleteAssets(withIDs: ids)
                    if succeeded {
                        await deletionEffectController.play(
                            effectToken,
                            animated: themeSettings.interfaceAnimationsEnabled && !reduceMotion
                        )
                        selectedIDs.removeAll()
                        isSelecting = false
                    } else {
                        deletionEffectController.discard(effectToken)
                    }
                }
            }
        } message: {
            Text("The system will ask you to confirm deletion of \(selectedIDs.count) photo or video item(s).")
        }
        .alert(
            AppL10n.string("Deletion Failed"),
            isPresented: Binding(
                get: {
                    if case .failure = viewModel.deletionState { return true }
                    return false
                },
                set: { if !$0 { viewModel.clearDeletionResult() } }
            )
        ) {
            Button("Done") { viewModel.clearDeletionResult() }
        } message: {
            if case let .failure(error) = viewModel.deletionState {
                Text(error.localizedDescription)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { previewAssetID != nil },
                set: { if !$0 { previewAssetID = nil } }
            )
        ) {
            if let previewAssetID {
                MediaPreviewGallery(
                    assetIDs: chronologicallySortedAssetIDs,
                    initialAssetID: previewAssetID,
                    protectedAssetIDs: protectedAssetIDs,
                    suggestedDeletionIDs: suggestedDeletionIDs,
                    viewModel: viewModel,
                    onDismiss: { self.previewAssetID = nil }
                )
            }
        }
        .onAppear {
            if (showsSimilarGroups || showsDateGroups) && !didInitializeSelection {
                didInitializeSelection = true
                isSelecting = true
                selectedIDs = Set(visibleAssetIDs).subtracting(protectedAssetIDs)
            }
            if showsSimilarGroups || showsDateGroups {
                viewModel.startCachingThumbnails(for: preheatedAssetIDs, targetSize: thumbnailTargetSize)
            }
        }
        .onDisappear {
            if showsSimilarGroups || showsDateGroups {
                viewModel.stopCachingThumbnails(for: preheatedAssetIDs, targetSize: thumbnailTargetSize)
            }
            viewModel.clearDeletionResult()
        }
        .onChange(of: visibleAssetIDs) { _, _ in
            reconcileSelection()
        }
        .onChange(of: viewModel.mediaAssetRevision) { _, _ in
            reconcileSelection()
        }
        // 触觉挂在稳定页面层，确保回执首次插入时也能触发。
        .sensoryFeedback(.success, trigger: deletionSuccessTrigger)
        .onAppear {
            tabBarVisibility.setHidden(
                true,
                source: "media.categoryDetail",
                scope: .media
            )
        }
        .onDisappear {
            tabBarVisibility.setHidden(
                false,
                source: "media.categoryDetail",
                scope: .media
            )
        }
    }

    private var selectedMediaSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: viewModel.estimatedByteCount(for: selectedIDs),
            countStyle: .file
        )
    }

    private var deletionSuccessTrigger: Int {
        if case let .success(deletedCount, _) = viewModel.deletionState {
            return deletedCount
        }
        return 0
    }

    /// 显示就地删除回执，并明确媒体进入“最近删除”后设备空间可能不会立即变化。
    private func deletionReceipt(deletedCount: Int, estimatedBytes: Int64) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .appTypeface(.title3, size: 20, relativeTo: .title3, weight: .regular)
                .foregroundStyle(theme.positiveGreen)

            VStack(alignment: .leading, spacing: 4) {
                Text("Moved to Recently Deleted")
                    .appTypeface(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline, weight: .semibold)

                HStack(spacing: 5) {
                    Text(
                        String.localizedStringWithFormat(
                            AppL10n.string("Items moved: %lld"),
                            Int64(deletedCount)
                        )
                    )
                    Text("·")
                    Text(
                        String.localizedStringWithFormat(
                            AppL10n.string("Estimated %@"),
                            ByteCountFormatter.string(
                                fromByteCount: estimatedBytes,
                                countStyle: .file
                            )
                        )
                    )
                }
                .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                .foregroundStyle(theme.textSecondary)

                 Text("These items still use storage until permanently deleted in Photos.")
                    .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer(minLength: 8)

            Button {
                viewModel.clearDeletionResult()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .appContentCard(cornerRadius: 18)
        .padding(.horizontal, 16)
    }
}

/// 展示单个资源的缩略图，并在需要时请求图片。
struct MediaAssetThumbnailView: View {
    let assetID: String
    @ObservedObject var viewModel: PhotoLibraryViewModel
    var targetSizeInPoints: CGSize? = nil
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var loadedAssetID: String?
    @State private var requestToken = UUID()

    private var targetPixelSize: CGSize {
        let size = targetSizeInPoints ?? CGSize(width: 140, height: 140)
        // Bucket nearby layout sizes to avoid a new request for fractional-point changes.
        func pixels(_ value: CGFloat) -> CGFloat { max(32, (value * displayScale / 32).rounded(.up) * 32) }
        return CGSize(width: pixels(size.width), height: pixels(size.height))
    }

    private struct LoadID: Equatable {
        let assetID: String
        let size: CGSize
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(.quaternary)
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: LoadID(assetID: assetID, size: targetPixelSize)) {
            loadImage()
        }
        .onDisappear {
            requestToken = UUID()
            if let requestID { viewModel.cancelThumbnail(requestID) }
            requestID = nil
        }
    }

    /// 低清预览可先显示，只有同尺寸的最终结果可以直接作为缓存命中。
    private func loadImage() {
        if let requestID { viewModel.cancelThumbnail(requestID) }
        requestID = nil
        let token = UUID()
        requestToken = token
        if loadedAssetID != assetID { image = nil }
        loadedAssetID = assetID
        let targetSize = targetPixelSize
        if let cachedImage = viewModel.cachedThumbnail(for: assetID, targetSize: targetSize) {
            image = cachedImage
            return
        }
        guard let asset = viewModel.asset(withIdentifier: assetID) else { return }
        requestID = viewModel.requestThumbnail(for: asset, targetSize: targetSize) { loadedImage in
            guard requestToken == token else { return }
            image = loadedImage
        }
    }
}

/// 提供媒体分析区域共用的卡片样式。
private extension View {
    /// 添加内边距并应用主题内容卡片样式。
    func mediaAnalysisCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appContentCard()
    }
}
