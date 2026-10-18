//
//  MediaQuickCleanViewModel.swift
//  CleanMyIPhone
//

import Combine
import Foundation
import Photos

@MainActor
final class MediaQuickCleanViewModel: ObservableObject {
    struct Category: Identifiable, Equatable {
        enum ID: String, CaseIterable {
            case similarPhotos
            case screenshots
            case videos
            case livePhotos
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


    init(photoLibrary: PhotoLibraryViewModel, canUseQuickClean: @escaping () -> Bool) {
        self.photoLibrary = photoLibrary
        self.canUseQuickClean = canUseQuickClean
        refreshCategories()
    }

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

    func estimatedByteCount(for category: Category) -> Int64 {
        if indexedSizeRevision == photoLibrary.mediaSizeRevision,
           let selectionIndex, let position = categories.firstIndex(where: { $0.id == category.id }) {
            return selectionIndex.summary(forCategoryAt: position).estimatedByteCount
        }
        return photoLibrary.estimatedByteCount(for: category.assetIDs)
    }

    func isSelected(_ category: Category) -> Bool {
        selectedCategoryIDs.contains(category.id)
    }

    func toggle(_ category: Category) {
        if selectedCategoryIDs.contains(category.id) {
            selectedCategoryIDs.remove(category.id)
        } else {
            selectedCategoryIDs.insert(category.id)
        }
    }

    func selectSuggestions() {
        selectedCategoryIDs = categories.contains { $0.id == .similarPhotos } ? [.similarPhotos] : []
    }

    func toggleAllCategories() {
        if allCategoriesSelected {
            selectedCategoryIDs.removeAll()
        } else {
            selectedCategoryIDs = Set(categories.map(\.id))
        }
    }

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

    func refreshCategories() {
        defer { refreshSelectionIndex() }
        guard let result = analysisResult else {
            categories = []
            selectedCategoryIDs.removeAll()
            return
        }

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

        // Use the actual category coverage so ordinary photos and retained similar
        // photos remain available for an explicit, independent selection.
        let coveredIDs = categories.reduce(into: Set<String>()) { $0.formUnion($1.assetIDs) }
        let otherIDs = Set(photoLibrary.assets.lazy.filter { $0.mediaType == .image }
            .map(\.localIdentifier)).subtracting(coveredIDs)
        if !otherIDs.isEmpty {
            categories.append(Category(id: .otherPhotos, title: AppL10n.string("Other Photos"),
                                       systemImage: "photo", assetIDs: otherIDs))
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
