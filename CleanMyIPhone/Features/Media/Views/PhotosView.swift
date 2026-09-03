//
//  PhotosView.swift
//  CleanMyIPhone
//

//
//  文件职责：声明 Photos 界面结构、交互入口与展示状态。
//  所属模块：CleanMyIPhone。
//

import Photos
import SwiftUI
//import UIKit

/// 定义 `PhotosView` 的值语义数据与相关行为。
struct PhotosView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeSettings: ThemeSettings
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let isTabActive: Bool
    @State private var animatedStorageFraction = 0.0

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Group {
                    switch viewModel.authorizationStatus {
                    case .notDetermined:
                        permissionView(
                            title: "Access your photos",
                            message: "Allow access to display the images in your Photos library.",
                            buttonTitle: "Allow Photo Access",
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink {
                        MediaQuickCleanView(photoLibrary: viewModel)
                    } label: {
                        Label("Quick Cleanup", systemImage: "trash")
                    }
                    .disabled(viewModel.assets.isEmpty || viewModel.isLoading)
                    .accessibilityIdentifier("media.quickClean.open")

                    Menu {
                        if viewModel.analysisState.isAnalyzing {
                            Button("Cancel Analysis", systemImage: "xmark.circle", role: .cancel) {
                                viewModel.cancelAnalysis()
                            }
                        } else {
                            Button("Analyze", systemImage: "sparkle.magnifyingglass") {
                                viewModel.startAnalysis()
                            }
                            .disabled(viewModel.assets.isEmpty || viewModel.isLoading)
                        }

                        Button("Refresh", systemImage: "arrow.clockwise") {
                            viewModel.refresh()
                        }
                    } label: {
                        Label("Media Actions", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("media.actions")
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadIfNeeded()
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

    @ViewBuilder
    private var mediaContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading media…")
        } else if viewModel.assets.isEmpty {
            ContentUnavailableView(
                "No Media",
                systemImage: "photo.on.rectangle",
                description: Text("No photos or videos are available in your library.")
            )
        } else {
            mediaDashboard
        }
    }

    @ViewBuilder
    private var limitedPhotoContent: some View {
        VStack(spacing: 12) {
            Label("Limited Photo Access", systemImage: "photo.badge.checkmark")
                .font(.headline)

            Text("Only the photos you selected are available to CleanMyIPhone.")
                .font(.subheadline)
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

    private var mediaDashboard: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 24) {
                Text("My Space")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .padding(.bottom, -16)

                storageOverview
                analysisContent
            }
            .padding(.horizontal, 4)
            .padding(.top, -24)
            .padding(.bottom, 24)
        }
        .appSoftScrollEdge()
    }

    @ViewBuilder
    private var analysisContent: some View {
        switch viewModel.analysisState {
        case .idle:
            VStack(alignment: .leading, spacing: 14) {
                Label("Smart Media Analysis", systemImage: "sparkles")
                    .font(.title2.bold())
                Text("Find visually similar photos and organize videos, screenshots, and Live Photos.")
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.startAnalysis()
                } label: {
                    Label("Find Similar Photos and Videos", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentPrimary)
            }
            .mediaAnalysisCard()

        case .analyzing(let progress):
            VStack(alignment: .leading, spacing: 10) {
                Text(analysisTitle(for: progress.phase))
                    .font(.headline)
                ProgressView(value: progress.fractionCompleted)
                    .tint(theme.accentPrimary)
                Text("Analyzed \(progress.completed) of \(progress.total)")
                    .font(.caption)
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

    /// 启动 `animateStorageBarIfNeeded` 动画，并确保展示状态与当前页面生命周期一致。
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

    /// 执行 `analysisTitle` 分析流程，在遵守文件访问边界的前提下生成结果。
    private func analysisTitle(for phase: MediaAnalysisPhase) -> LocalizedStringKey {
        switch phase {
        case .discovering: "Classifying videos…"
        case .generatingFeatures: "Analyzing image features…"
        case .comparingImages: "Grouping similar photos…"
        }
    }

    /// 封装 `permissionView` 对应的局部行为，供当前类型在统一入口下复用。
    private func permissionView(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        buttonTitle: LocalizedStringKey?,
        action: @escaping () -> Void
    ) -> some View {
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
    }
}

/// 定义 `MediaDashboardResultsView` 的值语义数据与相关行为。
private struct MediaDashboardResultsView: View {
    let result: MediaClassificationResult
    let isPartial: Bool
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleanup Recommendations")
                .font(.title2.bold())
                .padding(.horizontal, 12)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(cleanupCategories) { category in
                    categoryLink(category)
                }
            }

            Text("Media sizes are estimated without downloading original files.")
                .font(.caption)
                .foregroundStyle(.secondary)

            videoCategoryGrid

            if isPartial {
                Label(
                    "\(result.skippedImageCount) iCloud or unavailable image(s) were skipped.",
                    systemImage: "icloud.slash"
                )
                .font(.caption)
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
                systemImage: "photo.stack"
            ),
            MediaCategorySummary(
                title: AppL10n.string("Videos"),
                assetIDs: result.videoIDs,
                systemImage: "video.fill"
            ),
            MediaCategorySummary(
                title: AppL10n.string("Screenshots"),
                assetIDs: result.screenshotIDs,
                systemImage: "iphone"
            ),
            MediaCategorySummary(
                title: AppL10n.string("Live Photos"),
                assetIDs: result.livePhotoIDs,
                systemImage: "livephoto"
            )
        ]
    }

    private var videoCategories: [MediaCategorySummary] {
        VideoCategory.allCases.compactMap { category in
            let ids = result.classifiedVideos
                .filter { $0.categories.contains(category) }
                .map(\.id)
            guard !ids.isEmpty else { return nil }
            return MediaCategorySummary(
                title: category.displayName,
                assetIDs: ids,
                systemImage: videoCategorySymbol(category)
            )
        }
    }

    @ViewBuilder
    private var videoCategoryGrid: some View {
        if !videoCategories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Video Categories")
                    .font(.title2.bold())

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(videoCategories) { category in
                        categoryLink(category)
                    }
                }
            }
        }
    }

    /// 解析 `categoryLink` 对应的业务语义，并返回稳定的分类或映射结果。
    private func categoryLink(_ category: MediaCategorySummary) -> some View {
        NavigationLink {
            MediaCategoryDetailView(
                title: category.title,
                assetIDs: category.assetIDs,
                viewModel: viewModel
            )
        } label: {
            MediaCategoryCard(
                title: category.title,
                detail: categoryDetail(category.assetIDs),
                representativeAssetID: category.assetIDs.first,
                systemImage: category.systemImage,
                viewModel: viewModel
            )
        }
        .buttonStyle(.plain)
        .disabled(category.assetIDs.isEmpty)
    }

    /// 封装 `itemCount` 对应的局部行为，供当前类型在统一入口下复用。
    private func itemCount(_ count: Int) -> String {
        String.localizedStringWithFormat(AppL10n.string("%lld items"), Int64(count))
    }

    /// 解析 `categoryDetail` 对应的业务语义，并返回稳定的分类或映射结果。
    private func categoryDetail(_ assetIDs: [String]) -> String {
        "\(itemCount(assetIDs.count)) · \(estimatedSizeText(for: assetIDs))"
    }

    /// 封装 `estimatedSizeText` 对应的局部行为，供当前类型在统一入口下复用。
    private func estimatedSizeText(for assetIDs: [String]) -> String {
        let byteCount = viewModel.estimatedByteCount(for: Set(assetIDs))
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// 封装 `videoCategorySymbol` 对应的局部行为，供当前类型在统一入口下复用。
    private func videoCategorySymbol(_ category: VideoCategory) -> String {
        switch category {
        case .longDuration: "clock"
        case .fourK: "4k.tv"
        case .screenRecording: "record.circle"
        case .slowMotion: "slowmo"
        case .timeLapse: "timelapse"
        }
    }

}

/// 定义 `MediaStorageOverview` 的值语义数据与相关行为。
private struct MediaStorageOverview: View {
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
                    .font(.caption2)
                }
            }

            Text("Includes iOS, system data, and other app data.")
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)

            Text(storageSummary)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(14)
        .appContentCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    /// 计算 `fraction` 所需的派生值，避免展示层重复实现相同规则。
    private func fraction(for bytes: Int64) -> Double {
        guard storage.totalBytes > 0 else { return 0 }
        return min(max(Double(bytes) / Double(storage.totalBytes), 0), 1)
    }

    private var usedAnimationScale: Double {
        guard storage.usedFraction > 0 else { return 0 }
        return min(max(animatedUsedFraction / storage.usedFraction, 0), 1)
    }

    /// 封装 `displayWidths` 对应的局部行为，供当前类型在统一入口下复用。
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

    private var storageSummary: String {
        String.localizedStringWithFormat(
            AppL10n.string("%lld%% used · %@ of %@"),
            Int64((storage.usedFraction * 100).rounded()),
            byteCountText(storage.usedBytes),
            byteCountText(storage.totalBytes)
        )
    }

    /// 计算 `byteCountText` 所需的派生值，避免展示层重复实现相同规则。
    private func byteCountText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

/// 定义 `MediaStorageSegment` 的值语义数据与相关行为。
private struct MediaStorageSegment {
    let title: String
    let bytes: Int64
    let color: Color
}

/// 定义 `MediaCategorySummary` 的值语义数据与相关行为。
private struct MediaCategorySummary: Identifiable {
    let title: String
    let assetIDs: [String]
    let systemImage: String

    var id: String { title }
}

/// 定义 `MediaCategoryCard` 的值语义数据与相关行为。
private struct MediaCategoryCard: View {
    let title: String
    let detail: String
    let representativeAssetID: String?
    let systemImage: String
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let representativeAssetID {
                    GeometryReader { proxy in
                        MediaAssetThumbnailView(
                            assetID: representativeAssetID,
                            viewModel: viewModel
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    Image(systemName: systemImage)
                        .font(.largeTitle)
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
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(representativeAssetID == nil ? 0.62 : 1)
    }
}

/// 定义 `MediaCategoryDetailView` 的值语义数据与相关行为。
private struct MediaCategoryDetailView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var themeSettings: ThemeSettings
    let title: String
    let assetIDs: [String]
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var isDeleteConfirmationPresented = false
    @State private var previewAssetID: String?

    private var visibleAssetIDs: [String] {
        assetIDs.filter { viewModel.asset(withIdentifier: $0) != nil }
    }

    private var dateSections: [MediaDateSection] {
        MediaDateSectionBuilder.sections(
            from: visibleAssetIDs.compactMap { assetID in
                guard let asset = viewModel.asset(withIdentifier: assetID) else { return nil }
                return MediaDatedAsset(id: assetID, creationDate: asset.creationDate)
            }
        )
    }

    private var chronologicallySortedAssetIDs: [String] {
        dateSections.flatMap(\.assetIDs)
    }

    private var displayedSections: [MediaDateSection] {
        guard !themeSettings.mediaDateHeadersEnabled else { return dateSections }
        return [
            MediaDateSection(
                id: "all-media",
                day: nil,
                assetIDs: chronologicallySortedAssetIDs
            )
        ]
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
                } else {
                    MediaInteractiveGrid(
                        sections: displayedSections,
                        showsDateHeaders: themeSettings.mediaDateHeadersEnabled,
                        selectedIDs: $selectedIDs,
                        isSelecting: isSelecting,
                        viewModel: viewModel,
                        accentColor: theme.accentPrimary,
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
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button(selectedIDs.count == visibleAssetIDs.count ? "Deselect All" : "Select All") {
                        if selectedIDs.count == visibleAssetIDs.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(visibleAssetIDs)
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
                                .font(.subheadline.weight(.semibold))
                            Text("Estimated \(selectedMediaSizeText)")
                                .font(.caption)
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
                        .buttonStyle(.glass)
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
                Task {
                    await viewModel.deleteAssets(withIDs: ids)
                    if case .success = viewModel.deletionState {
                        selectedIDs.removeAll()
                        isSelecting = false
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
                    viewModel: viewModel,
                    onDismiss: { self.previewAssetID = nil }
                )
            }
        }
        .onAppear {
            viewModel.startCachingThumbnails(
                for: preheatedAssetIDs,
                targetSize: thumbnailTargetSize
            )
        }
        .onDisappear {
            viewModel.stopCachingThumbnails(
                for: preheatedAssetIDs,
                targetSize: thumbnailTargetSize
            )
            viewModel.clearDeletionResult()
        }
        // 触觉挂在稳定页面层，确保回执首次插入时也能触发。
        .sensoryFeedback(.success, trigger: deletionSuccessTrigger)
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
                .font(.title3)
                .foregroundStyle(theme.positiveGreen)

            VStack(alignment: .leading, spacing: 4) {
                Text("Moved to Recently Deleted")
                    .font(.subheadline.weight(.semibold))

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
                .font(.caption)
                .foregroundStyle(theme.textSecondary)

                Text("These items still use storage until permanently deleted in Photos.")
                    .font(.caption2)
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

/// 定义 `MediaAssetThumbnailView` 的值语义数据与相关行为。
struct MediaAssetThumbnailView: View {
    let assetID: String
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

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
        .task(id: assetID) {
            loadImage()
        }
        .onDisappear {
            if let requestID {
                viewModel.cancelThumbnail(requestID)
            }
        }
    }

    /// 加载 `loadImage` 所需的数据，并将结果转换为当前层可消费的状态。
    private func loadImage() {
        guard image == nil else { return }
        if let cachedImage = viewModel.cachedThumbnail(for: assetID) {
            image = cachedImage
            return
        }
        guard let asset = viewModel.asset(withIdentifier: assetID) else { return }

        requestID = viewModel.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 140 * displayScale, height: 140 * displayScale)
        ) { loadedImage in
            image = loadedImage
        }
    }
}

/// 扩展 `View`，集中实现当前文件所需的附加能力。
private extension View {
    /// 封装 `mediaAnalysisCard` 对应的局部行为，供当前类型在统一入口下复用。
    func mediaAnalysisCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appContentCard()
    }
}
