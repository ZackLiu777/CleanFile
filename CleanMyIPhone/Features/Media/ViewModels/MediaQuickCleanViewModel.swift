//
//  MediaQuickCleanViewModel.swift
//  CleanMyIPhone
//

import Combine
import Foundation

@MainActor
final class MediaQuickCleanViewModel: ObservableObject {
    struct Category: Identifiable, Equatable {
        enum ID: String, CaseIterable {
            case similarPhotos
            case screenshots
            case videos
            case livePhotos
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

    init(photoLibrary: PhotoLibraryViewModel) {
        self.photoLibrary = photoLibrary
        refreshCategories()
    }

    var selectedAssetIDs: Set<String> {
        categories
            .filter { selectedCategoryIDs.contains($0.id) }
            .reduce(into: Set<String>()) { result, category in
                result.formUnion(category.assetIDs)
            }
    }

    var selectedEstimatedByteCount: Int64 {
        photoLibrary.estimatedByteCount(for: selectedAssetIDs)
    }

    var allCategoriesSelected: Bool {
        !categories.isEmpty && selectedCategoryIDs.count == categories.count
    }

    func estimatedByteCount(for category: Category) -> Int64 {
        photoLibrary.estimatedByteCount(for: category.assetIDs)
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

    func toggleAllCategories() {
        if allCategoriesSelected {
            selectedCategoryIDs.removeAll()
        } else {
            selectedCategoryIDs = Set(categories.map(\.id))
        }
    }

    func deleteSelection() async {
        let identifiers = selectedAssetIDs
        guard !identifiers.isEmpty else { return }
        await photoLibrary.deleteAssets(withIDs: identifiers)
        if case .success = photoLibrary.deletionState {
            selectedCategoryIDs.removeAll()
            refreshCategories()
        }
    }

    func refreshCategories() {
        guard let result = analysisResult else {
            categories = []
            selectedCategoryIDs.removeAll()
            return
        }

        let similarDeletions = Set(
            result.similarImageGroups.flatMap { group in
                group.items.map(\.id).filter { $0 != group.suggestedKeeperID }
            }
        )
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

        let availableIDs = Set(categories.map(\.id))
        selectedCategoryIDs.formIntersection(availableIDs)
    }

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
        guard !assetIDs.isEmpty else { return nil }
        return Category(id: id, title: title, systemImage: systemImage, assetIDs: assetIDs)
    }
}
