//
//  PhotoLibraryViewModel.swift
//  CleanMyIPhone
//

import Combine
import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var isLoading = false
    @Published private(set) var analysisState: MediaAnalysisState = .idle
    @Published private(set) var deletionState: MediaDeletionState = .idle
    @Published private(set) var storageSnapshot: DeviceStorageSnapshot?

    private let imageManager = PHCachingImageManager()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let classificationService = MediaClassificationService()
    private let stateStore = AppStateStore.shared
    private let isRunningInPreviews: Bool
    private var analysisTask: Task<Void, Never>?
    private var hasLoadedLibrary = false
    private var assetsByIdentifier: [String: PHAsset] = [:]

    init() {
        let environment = ProcessInfo.processInfo.environment
        isRunningInPreviews = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        authorizationStatus = isRunningInPreviews
            ? .notDetermined
            : PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func refresh() {
        Task { await stateStore.saveMediaState(nil) }
        refreshLibrary(resetAnalysis: true)
    }

    private func refreshLibrary(resetAnalysis: Bool) {
        guard !isRunningInPreviews else { return }

        storageSnapshot = Self.loadStorageSnapshot()

        analysisTask?.cancel()
        analysisTask = nil
        if resetAnalysis {
            analysisState = .idle
        }

        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            assets = []
            rebuildAssetIndex()
            hasLoadedLibrary = true
            return
        }

        fetchAssets()
    }

    func loadIfNeeded() async {
        guard !hasLoadedLibrary else { return }
        hasLoadedLibrary = true
        let snapshot = await stateStore.loadMediaState()
        refreshLibrary(resetAnalysis: false)
        restoreAnalysis(from: snapshot)
    }

    func requestAccess() {
        guard !isRunningInPreviews else { return }

        isLoading = true

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.authorizationStatus = status
                self?.isLoading = false
                self?.fetchAssetsIfAllowed()
            }
        }
    }

    func presentLimitedLibraryPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootViewController = windowScene.windows
                .first(where: \.isKeyWindow)?.rootViewController else {
            return
        }

        var presenter = rootViewController
        while let presentedViewController = presenter.presentedViewController {
            presenter = presentedViewController
        }

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            Task { @MainActor in
                if let image {
                    self.thumbnailCache.setObject(image, forKey: asset.localIdentifier as NSString)
                }
                completion(image)
            }
        }
    }

    func asset(withIdentifier identifier: String) -> PHAsset? {
        assetsByIdentifier[identifier]
    }

    func cachedThumbnail(for identifier: String) -> UIImage? {
        thumbnailCache.object(forKey: identifier as NSString)
    }

    func estimatedByteCount(for assetIDs: Set<String>) -> Int64 {
        assetIDs.reduce(Int64.zero) { total, identifier in
            guard let asset = assetsByIdentifier[identifier] else { return total }
            return total + Self.estimatedByteCount(for: asset)
        }
    }

    func startCachingThumbnails(for assetIDs: ArraySlice<String>, targetSize: CGSize) {
        let assets = assetIDs.compactMap { assetsByIdentifier[$0] }
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    func stopCachingThumbnails(for assetIDs: ArraySlice<String>, targetSize: CGSize) {
        let assets = assetIDs.compactMap { assetsByIdentifier[$0] }
        guard !assets.isEmpty else { return }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func cancelThumbnail(_ requestID: PHImageRequestID) {
        imageManager.cancelImageRequest(requestID)
    }

    func requestPreviewImage(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            Task { @MainActor in completion(image) }
        }
    }

    func requestPlayerItem(
        for asset: PHAsset,
        completion: @escaping @MainActor (AVPlayerItem?) -> Void
    ) -> PHImageRequestID {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        return imageManager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
            Task { @MainActor in completion(item) }
        }
    }

    func requestLivePhoto(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping @MainActor (PHLivePhoto?) -> Void
    ) -> PHImageRequestID {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return imageManager.requestLivePhoto(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { livePhoto, _ in
            Task { @MainActor in completion(livePhoto) }
        }
    }

    func startAnalysis() {
        guard !analysisState.isAnalyzing else { return }
        guard !assets.isEmpty else {
            analysisState = .empty
            return
        }

        let assetsToAnalyze = assets
        Task { await stateStore.saveMediaState(nil) }
        analysisTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await classificationService.analyze(
                    assets: assetsToAnalyze,
                    progress: { [weak self] progress in
                        self?.analysisState = .analyzing(progress)
                    }
                )

                if result.skippedImageCount > 0 {
                    analysisState = .partialFailure(result)
                } else {
                    analysisState = .success(result)
                }
                persistAnalysisState()
            } catch is CancellationError {
                analysisState = .cancelled
            } catch {
                analysisState = .failure(.unexpected)
            }

            analysisTask = nil
        }
    }

    func cancelAnalysis() {
        guard analysisState.isAnalyzing else { return }
        analysisTask?.cancel()
        analysisTask = nil
        analysisState = .cancelled
    }

    func deleteAssets(withIDs assetIDs: Set<String>) async {
        guard !assetIDs.isEmpty else {
            deletionState = .failure(.noItemsSelected)
            return
        }
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            deletionState = .failure(.photoAccessUnavailable)
            return
        }

        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: Array(assetIDs),
            options: nil
        )
        guard fetchResult.count > 0 else {
            deletionState = .failure(.deletionFailed)
            return
        }

        deletionState = .deleting(itemCount: fetchResult.count)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
            let deletedIDs = Set((0..<fetchResult.count).map { fetchResult.object(at: $0).localIdentifier })
            assets.removeAll { deletedIDs.contains($0.localIdentifier) }
            rebuildAssetIndex()
            updateAnalysisAfterDeleting(deletedIDs)
            persistAnalysisState()
            storageSnapshot = Self.loadStorageSnapshot()
            deletionState = .success(deletedCount: deletedIDs.count)
        } catch {
            deletionState = .failure(.deletionFailed)
        }
    }

    func clearDeletionResult() {
        guard !deletionState.isDeleting else { return }
        deletionState = .idle
    }

    private func fetchAssetsIfAllowed() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            assets = []
            rebuildAssetIndex()
            return
        }

        fetchAssets()
    }

    private func fetchAssets() {
        isLoading = true

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)

        var fetchedAssets: [PHAsset] = []
        fetchedAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }

        assets = fetchedAssets
        rebuildAssetIndex()
        isLoading = false
    }

    private func rebuildAssetIndex() {
        assetsByIdentifier = Dictionary(
            uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) }
        )
    }

    private func updateAnalysisAfterDeleting(_ deletedIDs: Set<String>) {
        switch analysisState {
        case .success(let result):
            analysisState = .success(result.removingAssetIDs(deletedIDs))
        case .partialFailure(let result):
            analysisState = .partialFailure(result.removingAssetIDs(deletedIDs))
        default:
            break
        }
    }

    private func restoreAnalysis(from snapshot: MediaStateSnapshot?) {
        guard let snapshot else {
            if analysisState.isAnalyzing { analysisState = .cancelled }
            return
        }
        let availableIDs = Set(assetsByIdentifier.keys)
        let persistedIDs = Set(
            snapshot.result.similarImageIDs
                + snapshot.result.videoIDs
                + snapshot.result.screenshotIDs
                + snapshot.result.livePhotoIDs
        )
        let result = snapshot.result.removingAssetIDs(persistedIDs.subtracting(availableIDs))
        analysisState = snapshot.isPartial ? .partialFailure(result) : .success(result)
    }

    private func persistAnalysisState() {
        let snapshot: MediaStateSnapshot?
        switch analysisState {
        case .success(let result):
            snapshot = MediaStateSnapshot(result: result, isPartial: false)
        case .partialFailure(let result):
            snapshot = MediaStateSnapshot(result: result, isPartial: true)
        default:
            snapshot = nil
        }
        Task { await stateStore.saveMediaState(snapshot) }
    }

    private static func loadStorageSnapshot() -> DeviceStorageSnapshot? {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        guard let values = try? baseURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
              let totalCapacity = values.volumeTotalCapacity,
              let availableCapacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }

        return DeviceStorageSnapshot(
            totalBytes: Int64(totalCapacity),
            availableBytes: availableCapacity
        )
    }

    private static func estimatedByteCount(for asset: PHAsset) -> Int64 {
        let pixelCount = Double(max(asset.pixelWidth, 1) * max(asset.pixelHeight, 1))
        if asset.mediaType == .video {
            let bitsPerSecond: Double
            if max(asset.pixelWidth, asset.pixelHeight) >= 3_840 {
                bitsPerSecond = 35_000_000
            } else if max(asset.pixelWidth, asset.pixelHeight) >= 1_920 {
                bitsPerSecond = 10_000_000
            } else {
                bitsPerSecond = 4_000_000
            }
            return Int64(max(asset.duration, 1) * bitsPerSecond / 8)
        }

        // PhotoKit does not expose original resource byte size. This estimate avoids
        // reading full-resolution data or downloading iCloud assets just for a label.
        let stillImageBytes = pixelCount * 0.32
        let livePhotoVideoBytes = asset.mediaSubtypes.contains(.photoLive)
            ? 3_000_000.0
            : 0
        return Int64(stillImageBytes + livePhotoVideoBytes)
    }
}
