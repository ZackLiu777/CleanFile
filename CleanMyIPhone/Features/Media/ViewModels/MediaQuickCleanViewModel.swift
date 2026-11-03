// 快速清理分类、选择与删除协调。
// 不同分类可能包含同一资源，汇总按标识去重；可复用索引用于降低重复交互成本。
// 从相册分析结果构建分类，维护用户选择并计算数量与估算占用。
// 执行删除时重新检查功能权限，只有相册报告成功后才清除选择并刷新分类。

//
//  MediaQuickCleanViewModel.swift
//  CleanMyIPhone
//

import Combine
import Foundation
import Photos

/// 将相册分类转换为可选择的清理类别，并协调汇总估算及用户确认后的删除。
@MainActor
final class MediaQuickCleanViewModel: ObservableObject {
    /// 保存分类标识、展示信息和对应资源标识；多个分类可以指向同一资源。
    struct Category: Identifiable, Equatable {
        /// 稳定标识可供快速清理选择的媒体分类。
        enum ID: String, CaseIterable {
            case similarPhotos
            case screenshots
            case videos
            case livePhotos
            case cityPhotos
            case otherPhotos
            case screenRecordings
            case longVideos
            case fourKVideos
            case slowMotionVideos
        }

        let id: ID
        let title: String
        let systemImage: String
        let assetIDs: Set<String>
    }

    @Published private(set) var categories: [Category] = []
    @Published private(set) var selectedCategoryIDs = Set<Category.ID>()

    private unowned let photoLibrary: PhotoLibraryViewModel
    private let canUseQuickClean: () -> Bool
    @Published private var selectionIndex: MediaQuickCleanSelectionIndex?
    private var indexedSizeRevision: UInt64?
    private var indexGeneration: UInt64 = 0
    private var indexPreparation: Task<Void, Never>?


    /// 连接相册及权限检查，并从当前分析结果生成初始分类。
    init(photoLibrary: PhotoLibraryViewModel, canUseQuickClean: @escaping () -> Bool) {
        self.photoLibrary = photoLibrary
        self.canUseQuickClean = canUseQuickClean
        refreshCategories()
    }

    /// 合并所选分类的资源标识并去重，防止交叉分类重复计数或重复删除。
    var selectedAssetIDs: Set<String> {
        categories
            .filter { selectedCategoryIDs.contains($0.id) }
            .reduce(into: Set<String>()) { result, category in
                result.formUnion(category.assetIDs)
            }
    }

    var selectedAssetCount: Int {
        indexedSelectionSummary?.selectedCount ?? selectedAssetIDs.count
    }

    var selectedEstimatedByteCount: Int64 {
        indexedSelectionSummary?.estimatedByteCount ?? photoLibrary.estimatedByteCount(for: selectedAssetIDs)
    }

    /// 仅在大小修订号匹配时使用索引；位掩码对应当前分类顺序。
    private var indexedSelectionSummary: MediaQuickCleanSelectionIndex.Summary? {
        guard indexedSizeRevision == photoLibrary.mediaSizeRevision, let selectionIndex else { return nil }
        var mask: UInt16 = 0
        for (position, category) in categories.enumerated() where selectedCategoryIDs.contains(category.id) {
            mask |= UInt16(1 << position)
        }
        return selectionIndex.summary(forSelectionMask: mask)
    }

    var allCategoriesSelected: Bool {
        !categories.isEmpty && selectedCategoryIDs.count == categories.count
    }

    /// 优先使用与当前大小修订号匹配的索引，否则按分类资源估算。
    func estimatedByteCount(for category: Category) -> Int64 {
        if indexedSizeRevision == photoLibrary.mediaSizeRevision,
           let selectionIndex, let position = categories.firstIndex(where: { $0.id == category.id }) {
            return selectionIndex.summary(forCategoryAt: position).estimatedByteCount
        }
        return photoLibrary.estimatedByteCount(for: category.assetIDs)
    }

    /// 查询分类是否在当前选择集合中。
    func isSelected(_ category: Category) -> Bool {
        selectedCategoryIDs.contains(category.id)
    }

    /// 切换单个分类的选中状态。
    func toggle(_ category: Category) {
        if selectedCategoryIDs.contains(category.id) {
            selectedCategoryIDs.remove(category.id)
        } else {
            selectedCategoryIDs.insert(category.id)
        }
    }

    /// 将建议选择限定为相似照片分类；无该分类时清空选择。
    func selectSuggestions() {
        selectedCategoryIDs = categories.contains { $0.id == .similarPhotos } ? [.similarPhotos] : []
    }

    /// 全部已选时清空，否则选中当前所有可用分类。
    func toggleAllCategories() {
        if allCategoriesSelected {
            selectedCategoryIDs.removeAll()
        } else {
            selectedCategoryIDs = Set(categories.map(\.id))
        }
    }

    /// 执行前重新检查功能权限并合并资源；仅在删除成功后清除选择和刷新分类。
    @discardableResult
    func deleteSelection() async -> Bool {
        // Recheck at execution: a trial can expire while this screen or its confirmation is open.
        guard canUseQuickClean() else { return false }
        let identifiers = selectedAssetIDs
        guard !identifiers.isEmpty else { return false }
        let succeeded = await photoLibrary.deleteAssets(withIDs: identifiers)
        if succeeded {
            selectedCategoryIDs.removeAll()
            refreshCategories()
        }
        return succeeded
    }

    /// 从最新分析重建可用分类、保留仍有效的选择，并为未覆盖的图片生成其他照片分类。
    func refreshCategories() {
        defer { refreshSelectionIndex() }
        guard let result = analysisResult else {
            categories = []
            selectedCategoryIDs.removeAll()
            return
        }

        let previousCategories = categories
        let similarDeletions = result.suggestedCleanupIDs
        let classifiedVideos = result.classifiedVideos

        categories = [
            makeCategory(
                id: .similarPhotos,
                title: AppL10n.string("Similar Photos"),
                systemImage: "photo.stack",
                assetIDs: similarDeletions
            ),
            makeCategory(
                id: .screenshots,
                title: AppL10n.string("Screenshots"),
                systemImage: "iphone",
                assetIDs: Set(result.screenshotIDs)
            ),
            makeCategory(
                id: .videos,
                title: AppL10n.string("Videos"),
                systemImage: "video.fill",
                assetIDs: Set(result.videoIDs)
            ),
            makeCategory(
                id: .livePhotos,
                title: AppL10n.string("Live Photos"),
                systemImage: "livephoto",
                assetIDs: Set(result.livePhotoIDs)
            ),
            makeVideoCategory(
                id: .screenRecordings,
                title: AppL10n.string("Screen Recordings"),
                systemImage: "record.circle",
                category: .screenRecording,
                videos: classifiedVideos
            ),
            makeVideoCategory(
                id: .longVideos,
                title: AppL10n.string("Long Videos"),
                systemImage: "clock",
                category: .longDuration,
                videos: classifiedVideos
            ),
            makeVideoCategory(
                id: .fourKVideos,
                title: AppL10n.string("4K Videos"),
                systemImage: "4k.tv",
                category: .fourK,
                videos: classifiedVideos
            ),
            makeVideoCategory(
                id: .slowMotionVideos,
                title: AppL10n.string("Slow-motion Videos"),
                systemImage: "slowmo",
                category: .slowMotion,
                videos: classifiedVideos
            )
        ]
        .compactMap { $0 }

        for (id, title, icon, ids) in [
            (Category.ID.cityPhotos, AppL10n.string("City Photos"), "building.2", Set(photoLibrary.cityPhotoIDs))
        ] {
            if let category = makeCategory(id: id, title: title, systemImage: icon, assetIDs: ids) {
                categories.append(category)
            }
        }
        // 首页和快速清理对“其他”采用同一范围，避免包含已在相似组中的保留项。
        let otherIDs = Set(photoLibrary.otherPhotoIDs(excluding: result))
        if !otherIDs.isEmpty {
            categories.append(Category(id: .otherPhotos, title: AppL10n.string("Other Photos"),
                                       systemImage: "photo", assetIDs: otherIDs))
        }
        // A growing category must never silently add to an existing deletion selection.
        for category in categories where selectedCategoryIDs.contains(category.id) {
            if previousCategories.first(where: { $0.id == category.id })?.assetIDs != category.assetIDs {
                selectedCategoryIDs.remove(category.id)
            }
        }
        let availableIDs = Set(categories.map(\.id))
        selectedCategoryIDs.formIntersection(availableIDs)
    }

    /// First render keeps the legacy calculation; reuse the prepared index for repeated interactions.
    func refreshSelectionIndex() {
        indexGeneration &+= 1
        let generation = indexGeneration
        indexPreparation?.cancel()
        selectionIndex = nil
        indexedSizeRevision = nil
        guard !categories.isEmpty else { return }
        let groups = categories.map(\.assetIDs)
        indexPreparation = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            guard let self, !Task.isCancelled, self.indexGeneration == generation else { return }
            let revision = self.photoLibrary.mediaSizeRevision
            let identifiers = groups.reduce(into: Set<String>()) { $0.formUnion($1) }
            let estimates = self.photoLibrary.estimatedByteCounts(for: Array(identifiers))
            let worker = Task.detached(priority: .utility) {
                try? MediaQuickCleanSelectionIndex(categoryAssetIDs: groups, estimatedByteCountsByID: estimates)
            }
            let prepared = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, self.indexGeneration == generation,
                  self.photoLibrary.mediaSizeRevision == revision else { return }
            self.indexedSizeRevision = revision
            self.selectionIndex = prepared
        }
    }

    /// 取消索引准备并递增代次，阻止迟到的后台结果被安装。
    func cancelSelectionIndexPreparation() {
        indexGeneration &+= 1
        indexPreparation?.cancel()
        indexPreparation = nil
    }

    deinit { indexPreparation?.cancel() }

    private var analysisResult: MediaClassificationResult? {
        switch photoLibrary.analysisState {
        case .success(let result), .partialFailure(let result): result
        default: nil
        }
    }

    /// 根据视频的分类标签收集资源，再复用通用分类过滤规则。
    private func makeVideoCategory(
        id: Category.ID,
        title: String,
        systemImage: String,
        category: VideoCategory,
        videos: [ClassifiedVideo]
    ) -> Category? {
        makeCategory(
            id: id,
            title: title,
            systemImage: systemImage,
            assetIDs: Set(videos.filter { $0.categories.contains(category) }.map(\.id))
        )
    }

    /// 跳过空分类；除截图类别外排除建议保留的相似照片。
    private func makeCategory(
        id: Category.ID,
        title: String,
        systemImage: String,
        assetIDs: Set<String>
    ) -> Category? {
        // Screenshots are explicitly reviewed as their own category, including similar-photo keepers.
        let assetIDs = id == .screenshots ? assetIDs : assetIDs.subtracting(analysisResult?.protectedKeeperIDs ?? [])
        guard !assetIDs.isEmpty else { return nil }
        return Category(id: id, title: title, systemImage: systemImage, assetIDs: assetIDs)
    }
}
