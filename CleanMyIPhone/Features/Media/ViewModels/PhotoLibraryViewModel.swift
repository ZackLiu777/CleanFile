//
//  PhotoLibraryViewModel.swift
//  CleanMyIPhone
//

//
//  文件职责：协调 PhotoLibrary 页面状态、用户操作与底层服务。
//  所属模块：CleanMyIPhone。
//

import Combine
import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
/// 封装 `PhotoLibraryViewModel` 的引用语义、状态与业务行为。
final class PhotoLibraryViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var isLoading = false
    @Published private(set) var analysisState: MediaAnalysisState = .idle
    @Published private(set) var deletionState: MediaDeletionState = .idle
    @Published private(set) var storageSnapshot: DeviceStorageSnapshot?
    @Published private(set) var estimatedPhotoLibraryBytes: Int64 = 0
    @Published private(set) var estimatedVideoLibraryBytes: Int64 = 0
    @Published private(set) var exactByteCountsByIdentifier: [String: Int64] = [:]
    @Published private(set) var unavailableByteCountIdentifiers = Set<String>()

    private let imageManager = PHCachingImageManager()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let classificationService = MediaClassificationService()
    private let stateStore = AppStateStore.shared
    private let isRunningInPreviews: Bool
    private var analysisTask: Task<Void, Never>?
    private var analysisGeneration = 0
    private var hasLoadedLibrary = false
    private var assetsByIdentifier: [String: PHAsset] = [:]
    private var displayNamesByIdentifier: [String: String] = [:]
    private var pendingByteCountIdentifiers: [String] = []
    private var pendingByteCountIdentifierSet = Set<String>()
    private var byteCountTasks: [String: Task<Void, Never>] = [:]
    private var mediaSizeIndexSaveTask: Task<Void, Never>?
    private var mediaSizeRecalculationTask: Task<Void, Never>?
    // Exact sizes require PhotoKit to stream the resource. Keep this bounded, but allow
    // enough visible cells to make progress when one of them is backed by iCloud.
    private let maximumConcurrentByteCountRequests = 6

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init() {
        let environment = ProcessInfo.processInfo.environment
        isRunningInPreviews = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        authorizationStatus = isRunningInPreviews
            ? .notDetermined
            : PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 更新 `refresh` 对应的数据，使界面状态与底层结果保持一致。
    func refresh() {
        Task { await stateStore.saveMediaState(nil) }
        refreshLibrary(resetAnalysis: true)
        startAnalysis()
    }

    /// 更新 `refreshLibrary` 对应的数据，使界面状态与底层结果保持一致。
    private func refreshLibrary(resetAnalysis: Bool) {
        guard !isRunningInPreviews else { return }

        storageSnapshot = Self.loadStorageSnapshot()

        analysisGeneration &+= 1
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

    /// 加载 `loadIfNeeded` 所需的数据，并将结果转换为当前层可消费的状态。
    func loadIfNeeded() async {
        guard !hasLoadedLibrary else { return }
        hasLoadedLibrary = true
        async let stateSnapshot = stateStore.loadMediaState()
        async let sizeSnapshot = stateStore.loadMediaSizeIndex()
        let (snapshot, persistedSizes) = await (stateSnapshot, sizeSnapshot)
        refreshLibrary(resetAnalysis: false)
        restoreMediaSizeIndex(from: persistedSizes)
        restoreAnalysis(from: snapshot)
    }

    /// 封装 `requestAccess` 对应的局部行为，供当前类型在统一入口下复用。
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

    /// 控制 `presentLimitedLibraryPicker` 对应界面或资源的展示生命周期。
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

    /// 控制 `openSettings` 对应界面或资源的展示生命周期。
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 封装 `requestThumbnail` 对应的局部行为，供当前类型在统一入口下复用。
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

    /// 封装 `asset` 对应的局部行为，供当前类型在统一入口下复用。
    func asset(withIdentifier identifier: String) -> PHAsset? {
        assetsByIdentifier[identifier]
    }

    /// 封装 `cachedThumbnail` 对应的局部行为，供当前类型在统一入口下复用。
    func cachedThumbnail(for identifier: String) -> UIImage? {
        thumbnailCache.object(forKey: identifier as NSString)
    }

    /// 封装 `estimatedByteCount` 对应的局部行为，供当前类型在统一入口下复用。
    func estimatedByteCount(for assetIDs: Set<String>) -> Int64 {
        let calibration = makeMediaSizeCalibration()
        return assetIDs.reduce(Int64.zero) { total, identifier in
            guard let asset = assetsByIdentifier[identifier] else { return total }
            return total + calibratedByteCount(for: asset, calibration: calibration)
        }
    }

    /// 封装 `displayName` 对应的局部行为，供当前类型在统一入口下复用。
    func displayName(for assetID: String) -> String {
        if let cachedName = displayNamesByIdentifier[assetID] {
            return cachedName
        }
        guard let asset = assetsByIdentifier[assetID] else { return "" }

        let resource = PHAssetResource.assetResources(for: asset).first { resource in
            switch asset.mediaType {
            case .image:
                resource.type == .photo || resource.type == .fullSizePhoto
            case .video:
                resource.type == .video || resource.type == .fullSizeVideo
            default:
                false
            }
        } ?? PHAssetResource.assetResources(for: asset).first

        let originalName = resource?.originalFilename ?? ""
        let name = (originalName as NSString).deletingPathExtension
        displayNamesByIdentifier[assetID] = name
        return name
    }

    /// 封装 `estimatedByteCount` 对应的局部行为，供当前类型在统一入口下复用。
    func estimatedByteCount(for assetID: String) -> Int64 {
        guard let asset = assetsByIdentifier[assetID] else { return 0 }
        return calibratedByteCount(for: asset, calibration: makeMediaSizeCalibration())
    }

    func exactByteCount(for assetID: String) -> Int64? {
        exactByteCountsByIdentifier[assetID]
    }

    func isExactByteCountUnavailable(for assetID: String) -> Bool {
        unavailableByteCountIdentifiers.contains(assetID)
    }

    /// Queues a bounded, streaming request for the asset's real underlying resource size.
    func requestExactByteCount(for assetID: String) {
        guard exactByteCountsByIdentifier[assetID] == nil,
              !unavailableByteCountIdentifiers.contains(assetID),
              byteCountTasks[assetID] == nil,
              !pendingByteCountIdentifierSet.contains(assetID),
              assetsByIdentifier[assetID] != nil else { return }

        pendingByteCountIdentifiers.append(assetID)
        pendingByteCountIdentifierSet.insert(assetID)
        startPendingByteCountRequests()
    }

    /// Stops data reads when the media detail page is no longer visible.
    func cancelExactByteCountRequests() {
        pendingByteCountIdentifiers.removeAll()
        pendingByteCountIdentifierSet.removeAll()
        byteCountTasks.values.forEach { $0.cancel() }
        byteCountTasks.removeAll()
    }

    private func startPendingByteCountRequests() {
        while byteCountTasks.count < maximumConcurrentByteCountRequests,
              let assetID = pendingByteCountIdentifiers.first {
            pendingByteCountIdentifiers.removeFirst()
            pendingByteCountIdentifierSet.remove(assetID)
            guard let asset = assetsByIdentifier[assetID] else { continue }
            let resources = Self.displayResources(for: asset)

            byteCountTasks[assetID] = Task { [weak self] in
                do {
                    let byteCount = try await MediaAssetResourceByteCounter.byteCount(
                        for: resources
                    )
                    try Task.checkCancellation()
                    self?.exactByteCountsByIdentifier[assetID] = byteCount
                    self?.scheduleLibraryByteCountRecalculation()
                    self?.scheduleMediaSizeIndexSave()
                } catch is CancellationError {
                    // Leaving the detail page is expected and must not mark the resource unavailable.
                } catch {
                    self?.unavailableByteCountIdentifiers.insert(assetID)
                }
                self?.byteCountTasks[assetID] = nil
                self?.startPendingByteCountRequests()
            }
        }
    }

    private static func displayResources(for asset: PHAsset) -> [PHAssetResource] {
        let resources = PHAssetResource.assetResources(for: asset)

        switch asset.mediaType {
        case .image:
            // `.photo` is the image represented by the asset. Reading both it and
            // `.fullSizePhoto` counted two renditions of edited photos and could force
            // an unnecessary iCloud download. A Live Photo additionally owns one
            // paired video, which is part of the item the user sees.
            guard let photo = firstResource(
                in: resources,
                preferredTypes: [.photo, .fullSizePhoto, .alternatePhoto]
            ) else { return [] }

            guard asset.mediaSubtypes.contains(.photoLive),
                  let pairedVideo = firstResource(
                      in: resources,
                      preferredTypes: [.pairedVideo, .fullSizePairedVideo]
                  ) else { return [photo] }
            return [photo, pairedVideo]

        case .video:
            return firstResource(
                in: resources,
                preferredTypes: [.video, .fullSizeVideo]
            ).map { [$0] } ?? []

        case .audio:
            return firstResource(in: resources, preferredTypes: [.audio]).map { [$0] } ?? []

        default:
            return []
        }
    }

    private static func firstResource(
        in resources: [PHAssetResource],
        preferredTypes: [PHAssetResourceType]
    ) -> PHAssetResource? {
        for type in preferredTypes {
            if let resource = resources.first(where: { $0.type == type }) {
                return resource
            }
        }
        return nil
    }

    /// 启动 `startCachingThumbnails` 对应流程，并初始化本轮任务需要的状态。
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

    /// 取消 `stopCachingThumbnails` 对应的进行中任务，并收敛到可继续操作的状态。
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

    /// 取消 `cancelThumbnail` 对应的进行中任务，并收敛到可继续操作的状态。
    func cancelThumbnail(_ requestID: PHImageRequestID) {
        imageManager.cancelImageRequest(requestID)
    }

    /// 封装 `requestPreviewImage` 对应的局部行为，供当前类型在统一入口下复用。
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

    /// 封装 `requestPlayerItem` 对应的局部行为，供当前类型在统一入口下复用。
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

    /// 封装 `requestLivePhoto` 对应的局部行为，供当前类型在统一入口下复用。
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

    /// 启动 `startAnalysis` 对应流程，并初始化本轮任务需要的状态。
    func startAnalysis() {
        guard !analysisState.isAnalyzing else { return }
        guard !assets.isEmpty else {
            analysisState = .empty
            return
        }

        let assetsToAnalyze = assets
        analysisGeneration &+= 1
        let generation = analysisGeneration
        Task { await stateStore.saveMediaState(nil) }
        analysisTask = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await classificationService.analyze(
                    assets: assetsToAnalyze,
                    progress: { [weak self] progress in
                        guard self?.analysisGeneration == generation else { return }
                        self?.analysisState = .analyzing(progress)
                    }
                )
                guard generation == analysisGeneration else { return }

                if result.skippedImageCount > 0 {
                    analysisState = .partialFailure(result)
                } else {
                    analysisState = .success(result)
                }
                persistAnalysisState()
            } catch is CancellationError {
                guard generation == analysisGeneration else { return }
                analysisState = .cancelled
            } catch {
                guard generation == analysisGeneration else { return }
                analysisState = .failure(.unexpected)
            }

            if generation == analysisGeneration {
                analysisTask = nil
            }
        }
    }

    /// 取消 `cancelAnalysis` 对应的进行中任务，并收敛到可继续操作的状态。
    func cancelAnalysis() {
        guard analysisState.isAnalyzing else { return }
        analysisGeneration &+= 1
        analysisTask?.cancel()
        analysisTask = nil
        analysisState = .cancelled
    }

    /// 执行 `deleteAssets` 移除流程，并同步更新受影响的业务状态。
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
        // PhotoKit 可能在确认前移除部分资源；禁止把剩余资源静默当作完整批次删除。
        guard fetchResult.count == assetIDs.count else {
            deletionState = .failure(.itemsUnavailable)
            return
        }

        let deletedIDs = Set((0..<fetchResult.count).map { fetchResult.object(at: $0).localIdentifier })
        let estimatedBytes = estimatedByteCount(for: deletedIDs)
        deletionState = .deleting(itemCount: fetchResult.count)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
            assets.removeAll { deletedIDs.contains($0.localIdentifier) }
            deletedIDs.forEach { exactByteCountsByIdentifier[$0] = nil }
            rebuildAssetIndex()
            scheduleMediaSizeIndexSave()
            updateAnalysisAfterDeleting(deletedIDs)
            persistAnalysisState()
            storageSnapshot = Self.loadStorageSnapshot()
            deletionState = .success(
                deletedCount: deletedIDs.count,
                estimatedBytes: estimatedBytes
            )
        } catch {
            let photoError = error as NSError
            if photoError.domain == PHPhotosError.errorDomain,
               photoError.code == PHPhotosError.Code.userCancelled.rawValue {
                // 取消系统确认不是失败；回到可操作状态并保留当前选择。
                deletionState = .idle
                return
            }
            deletionState = .failure(.deletionFailed)
        }
    }

    /// 重置 `clearDeletionResult` 管理的状态，避免旧任务或旧数据影响下一次操作。
    func clearDeletionResult() {
        guard !deletionState.isDeleting else { return }
        deletionState = .idle
    }

    /// 加载 `fetchAssetsIfAllowed` 所需的数据，并将结果转换为当前层可消费的状态。
    private func fetchAssetsIfAllowed() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            assets = []
            rebuildAssetIndex()
            return
        }

        fetchAssets()
    }

    /// 加载 `fetchAssets` 所需的数据，并将结果转换为当前层可消费的状态。
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

    /// 封装 `rebuildAssetIndex` 对应的局部行为，供当前类型在统一入口下复用。
    private func rebuildAssetIndex() {
        assetsByIdentifier = Dictionary(
            uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) }
        )
        exactByteCountsByIdentifier = exactByteCountsByIdentifier.filter {
            assetsByIdentifier[$0.key] != nil
        }
        recalculateLibraryByteCounts()
        displayNamesByIdentifier = displayNamesByIdentifier.filter {
            assetsByIdentifier[$0.key] != nil
        }
    }

    private func recalculateLibraryByteCounts() {
        let calibration = makeMediaSizeCalibration()
        estimatedPhotoLibraryBytes = assets.lazy
            .filter { $0.mediaType == .image }
            .reduce(Int64.zero) {
                $0 + calibratedByteCount(for: $1, calibration: calibration)
            }
        estimatedVideoLibraryBytes = assets.lazy
            .filter { $0.mediaType == .video }
            .reduce(Int64.zero) {
                $0 + calibratedByteCount(for: $1, calibration: calibration)
            }
    }

    /// Coalesces a burst of PhotoKit completions so a large library is not reduced
    /// repeatedly on the main actor for every individual asset.
    private func scheduleLibraryByteCountRecalculation() {
        mediaSizeRecalculationTask?.cancel()
        mediaSizeRecalculationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.recalculateLibraryByteCounts()
        }
    }

    private func calibratedByteCount(
        for asset: PHAsset,
        calibration: [String: Double]
    ) -> Int64 {
        if let exact = exactByteCountsByIdentifier[asset.localIdentifier] {
            return exact
        }

        let denominator = Self.calibrationDenominator(for: asset)
        guard denominator > 0,
              let coefficient = calibration[Self.calibrationKey(for: asset)] else {
            return Self.fallbackEstimatedByteCount(for: asset)
        }
        return Int64((denominator * coefficient).rounded())
    }

    /// Uses medians so a single unusually compressible screenshot or high-bitrate video
    /// cannot distort every item in the same library group.
    private func makeMediaSizeCalibration() -> [String: Double] {
        var samples: [String: [Double]] = [:]
        for (identifier, byteCount) in exactByteCountsByIdentifier {
            guard let asset = assetsByIdentifier[identifier] else { continue }
            let denominator = Self.calibrationDenominator(for: asset)
            guard denominator > 0 else { continue }
            samples[Self.calibrationKey(for: asset), default: []]
                .append(Double(byteCount) / denominator)
        }

        return samples.compactMapValues { values in
            // Fewer than three verified items are retained in the index but are not
            // enough to define a reliable coefficient for the rest of the group.
            guard values.count >= 3 else { return nil }
            let sorted = values.sorted()
            let middle = sorted.count / 2
            if sorted.count.isMultiple(of: 2) {
                return (sorted[middle - 1] + sorted[middle]) / 2
            }
            return sorted[middle]
        }
    }

    private static func calibrationDenominator(for asset: PHAsset) -> Double {
        if asset.mediaType == .video {
            return max(asset.duration, 1)
        }
        return Double(max(asset.pixelWidth, 1)) * Double(max(asset.pixelHeight, 1))
    }

    private static func calibrationKey(for asset: PHAsset) -> String {
        let format = asset.contentType.identifier.lowercased()
        if asset.mediaType == .video {
            let longestEdge = max(asset.pixelWidth, asset.pixelHeight)
            let resolution = longestEdge >= 3_840 ? "4k" : longestEdge >= 1_920 ? "1080" : "small"
            let subtype = asset.mediaSubtypes.contains(.videoHighFrameRate) ? "high-fps" : "standard"
            return "video|\(format)|\(resolution)|\(subtype)"
        }

        let pixels = max(asset.pixelWidth, 1) * max(asset.pixelHeight, 1)
        let resolution: String
        switch pixels {
        case ..<4_000_000: resolution = "small"
        case ..<10_000_000: resolution = "medium"
        case ..<20_000_000: resolution = "large"
        default: resolution = "very-large"
        }
        let subtype: String
        if asset.mediaSubtypes.contains(.photoLive) {
            subtype = "live"
        } else if asset.mediaSubtypes.contains(.photoScreenshot) {
            subtype = "screenshot"
        } else if asset.mediaSubtypes.contains(.photoPanorama) {
            subtype = "panorama"
        } else {
            subtype = "standard"
        }
        return "image|\(format)|\(resolution)|\(subtype)"
    }

    private func restoreMediaSizeIndex(from snapshot: MediaSizeIndexSnapshot?) {
        guard let snapshot else { return }
        exactByteCountsByIdentifier = snapshot.entries.reduce(into: [:]) { result, pair in
            guard let asset = assetsByIdentifier[pair.key],
                  asset.modificationDate == pair.value.modificationDate,
                  pair.value.byteCount >= 0 else { return }
            result[pair.key] = pair.value.byteCount
        }
        recalculateLibraryByteCounts()
    }

    private func scheduleMediaSizeIndexSave() {
        mediaSizeIndexSaveTask?.cancel()
        let entries = exactByteCountsByIdentifier.reduce(
            into: [String: MediaSizeIndexEntry]()
        ) { result, pair in
            guard let asset = assetsByIdentifier[pair.key] else { return }
            result[pair.key] = MediaSizeIndexEntry(
                modificationDate: asset.modificationDate,
                byteCount: pair.value
            )
        }
        let snapshot = MediaSizeIndexSnapshot(entries: entries)
        mediaSizeIndexSaveTask = Task { [stateStore] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await stateStore.saveMediaSizeIndex(snapshot)
        }
    }

    /// 更新 `updateAnalysisAfterDeleting` 对应的数据，使界面状态与底层结果保持一致。
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

    /// 加载 `restoreAnalysis` 所需的数据，并将结果转换为当前层可消费的状态。
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

    /// 持久化 `persistAnalysisState` 对应的数据，并保持后续恢复所需的信息完整。
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

    /// 加载 `loadStorageSnapshot` 所需的数据，并将结果转换为当前层可消费的状态。
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

    /// 封装 `estimatedByteCount` 对应的局部行为，供当前类型在统一入口下复用。
    private static func fallbackEstimatedByteCount(for asset: PHAsset) -> Int64 {
        let pixelCount = Double(max(asset.pixelWidth, 1)) * Double(max(asset.pixelHeight, 1))
        if asset.mediaType == .video {
            let bitsPerSecond: Double
            if max(asset.pixelWidth, asset.pixelHeight) >= 3_840 {
                bitsPerSecond = 42_000_000
            } else if max(asset.pixelWidth, asset.pixelHeight) >= 1_920 {
                bitsPerSecond = 12_000_000
            } else {
                bitsPerSecond = 5_000_000
            }
            let frameRateMultiplier = asset.mediaSubtypes.contains(.videoHighFrameRate) ? 1.45 : 1
            return Int64(max(asset.duration, 1) * bitsPerSecond * frameRateMultiplier / 8)
        }

        let format = asset.contentType.identifier.lowercased()
        let bytesPerPixel: Double
        if format.contains("heic") || format.contains("heif") {
            bytesPerPixel = 0.22
        } else if format.contains("png") {
            bytesPerPixel = asset.mediaSubtypes.contains(.photoScreenshot) ? 0.38 : 0.72
        } else if format.contains("raw") || format.contains("dng") {
            bytesPerPixel = 1.9
        } else {
            bytesPerPixel = 0.48
        }
        let stillImageBytes = pixelCount * bytesPerPixel
        let livePhotoVideoBytes = asset.mediaSubtypes.contains(.photoLive)
            ? max(pixelCount * 0.24, 2_500_000)
            : 0
        return Int64(stillImageBytes + livePhotoVideoBytes)
    }
}

/// Counts PhotoKit resource chunks without retaining complete photos or videos in memory.
private enum MediaAssetResourceByteCounter {
    static func byteCount(for resources: [PHAssetResource]) async throws -> Int64 {
        guard !resources.isEmpty else { throw MediaAssetResourceByteCountError.noResources }
        var total: Int64 = 0
        for resource in resources {
            try Task.checkCancellation()
            total += try await byteCount(for: resource)
        }
        return total
    }

    private static func byteCount(for resource: PHAssetResource) async throws -> Int64 {
        let accumulator = MediaAssetResourceByteAccumulator()
        let request = MediaAssetResourceRequestToken()
        let manager = PHAssetResourceManager.default()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = manager.requestData(
                    for: resource,
                    options: options,
                    dataReceivedHandler: { data in
                        accumulator.add(data.count)
                    },
                    completionHandler: { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: accumulator.value)
                        }
                    }
                )
                request.store(requestID, manager: manager)
            }
        } onCancel: {
            request.cancel()
        }
    }
}

private enum MediaAssetResourceByteCountError: Error {
    case noResources
}

private final class MediaAssetResourceByteAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var byteCount: Int64 = 0

    func add(_ count: Int) {
        lock.lock()
        byteCount += Int64(count)
        lock.unlock()
    }

    var value: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return byteCount
    }
}

private final class MediaAssetResourceRequestToken: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var requestID: PHAssetResourceDataRequestID?
    nonisolated(unsafe) private weak var manager: PHAssetResourceManager?
    nonisolated(unsafe) private var isCancelled = false

    nonisolated func store(
        _ requestID: PHAssetResourceDataRequestID,
        manager: PHAssetResourceManager
    ) {
        lock.lock()
        self.requestID = requestID
        self.manager = manager
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { manager.cancelDataRequest(requestID) }
    }

    nonisolated func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        let manager = manager
        lock.unlock()
        if let requestID { manager?.cancelDataRequest(requestID) }
    }
}
