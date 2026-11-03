// PhotoKit 授权、资源清单、分析和界面状态。
// 通过代次防止旧分析覆盖新状态；精确大小读取受并发限制，缓存仅在资源元数据匹配时恢复。
// 页面通过此模型请求授权、缩略图和预览，并读取资源清单、分类进度与删除结果。
// PhotoKit 操作和后台分析的生命周期与界面状态分开；用户确认后才提交资源删除。

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

/// 协调 PhotoKit 授权、资源清单、分析、删除及大小估算的界面状态。
@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    /// Process-lifetime gate: a cold launch analyzes once, while tab changes,
    /// view reconstruction, and foreground transitions do not restart the scan.
    private static var didStartColdLaunchAnalysis = false

    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var mediaAssetRevision: UInt64 = 0
    @Published private(set) var mediaSizeRevision: UInt64 = 0
    @Published private(set) var assets: [PHAsset] = [] {
        didSet {
            mediaAssetRevision &+= 1
            mediaSizeRevision &+= 1
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var analysisState: MediaAnalysisState = .idle
    @Published private(set) var deletionState: MediaDeletionState = .idle
    @Published private(set) var storageSnapshot: DeviceStorageSnapshot?
    @Published private(set) var estimatedPhotoLibraryBytes: Int64 = 0
    @Published private(set) var estimatedVideoLibraryBytes: Int64 = 0
    @Published private(set) var exactByteCountsByIdentifier: [String: Int64] = [:] {
        didSet { mediaSizeRevision &+= 1 }
    }
    @Published private(set) var unavailableByteCountIdentifiers = Set<String>()

    private let imageManager = PHCachingImageManager()
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()
    private var calibrationRevision: UInt64?
    private var cachedCalibration: [String: Double] = [:]
    private let sizedThumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private let classificationService = MediaClassificationService()
    private let inventory = MediaLibraryInventory()
    private let stateStore = AppStateStore.shared
    private let isRunningInPreviews: Bool
    @Published private(set) var cityPhotoIDs: [String] = []
    private var sceneTask: Task<Void, Never>?
    private var sceneGeneration = 0
    private var analysisTask: Task<Void, Never>?
    private var analysisGeneration = 0
    private var hasLoadedLibrary = false
    private var initialLoadTask: Task<Void, Never>?
    private var storageSnapshotTask: Task<Void, Never>?
    private var libraryRevision: MediaLibraryRevision?
    private var assetsByIdentifier: [String: PHAsset] = [:]
    private var displayNamesByIdentifier: [String: String] = [:]
    private var pendingByteCountIdentifiers: [String] = []
    private var longPendingByteCountIdentifiers: MediaSizeRequestQueue?
    private var pendingByteCountIdentifierSet = Set<String>()
    private var byteCountTasks: [String: Task<Void, Never>] = [:]
    private var mediaSizeIndexSaveTask: Task<Void, Never>?
    private var mediaSizeRecalculationTask: Task<Void, Never>?
    // Exact sizes require PhotoKit to stream the resource. Keep this bounded, but allow
    // enough visible cells to make progress when one of them is backed by iCloud.
    private let maximumConcurrentByteCountRequests = 6

    /// 读取当前相册授权状态；预览环境不触发真实相册访问。
    init() {
        let environment = ProcessInfo.processInfo.environment
        isRunningInPreviews = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        authorizationStatus = isRunningInPreviews
            ? .notDetermined
            : PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// 刷新相册资源后启动新一轮分析。
    func refresh() {
        refreshLibrary(resetAnalysis: true)
        startAnalysis()
    }

    /// 刷新容量与资源清单，取消过期分析，并按调用方要求重置分析状态。
    private func refreshLibrary(resetAnalysis: Bool) {
        guard !isRunningInPreviews else { return }

        refreshStorageSnapshot()

        sceneGeneration &+= 1
        sceneTask?.cancel()
        cityPhotoIDs = []
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

    /// Overlap disk/PhotoKit initialization with the original opening animation.
    /// A view reconstruction joins this load instead of starting another one.
    func loadIfNeeded() async {
        guard !isRunningInPreviews else { return }
        if let initialLoadTask {
            await initialLoadTask.value
            return
        }
        guard !hasLoadedLibrary else { return }
        let generation = analysisGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            defer { initialLoadTask = nil }
            await loadInitialLibrary(generation: generation)
        }
        initialLoadTask = task
        await task.value
    }

    /// 并行读取持久化快照与资源清单；仅在代次仍有效时恢复数据并决定是否重新分析。
    private func loadInitialLibrary(generation: Int) async {
        let interval = MediaPerformance.begin("Media Initial Load")
        defer { MediaPerformance.end("Media Initial Load", id: interval) }
        isLoading = true
        defer {
            if generation == analysisGeneration { isLoading = false }
        }
        // Device capacity does not require Photos permission. Start it even when
        // this launch still needs the user to grant access to the photo library.
        refreshStorageSnapshot()
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            hasLoadedLibrary = true
            return
        }

        async let stateSnapshot = stateStore.loadMediaState()
        async let sizeSnapshot = stateStore.loadMediaSizeIndex()
        let fetchedAssets: [PHAsset]
        do {
            fetchedAssets = try await inventory.fetch()
        } catch {
            return
        }
        let (snapshot, persistedSizes) = await (stateSnapshot, sizeSnapshot)
        guard generation == analysisGeneration, !Task.isCancelled else { return }
        assets = fetchedAssets
        rebuildAssetIndex()
        restoreMediaSizeIndex(from: persistedSizes)
        hasLoadedLibrary = true
        let canReuseAnalysis = restoreAnalysis(from: snapshot)
        isLoading = false
        startColdLaunchAnalysisIfNeeded(requiresAnalysis: !canReuseAnalysis)
        if canReuseAnalysis, let snapshot { startSceneAnalysis(result: snapshot.result) }
    }

    /// 场景扫描独立于清理分析，避免阻塞首页和改变清理建议。
    private func startSceneAnalysis(result: MediaClassificationResult) {
        sceneGeneration &+= 1
        let generation = sceneGeneration
        sceneTask?.cancel()
        let excluded = result.suggestedCleanupIDs.union(result.screenshotIDs).union(result.livePhotoIDs)
        let currentAssets = assets
        sceneTask = Task { [weak self] in
            guard let self else { return }
            await classificationService.classifyScenes(assets: currentAssets, excludedIDs: excluded) { [weak self] city in
                guard let self, self.sceneGeneration == generation else { return }
                self.cityPhotoIDs = city
            }
        }
    }

    /// 其他照片排除已展示在首页任一照片分类中的资源，包括相似组的保留项。
    func otherPhotoIDs(excluding result: MediaClassificationResult) -> [String] {
        var covered = Set(result.similarImageIDs)
        covered.formUnion(result.screenshotIDs)
        covered.formUnion(result.livePhotoIDs)
        covered.formUnion(cityPhotoIDs)
        return assets.compactMap { asset in
            asset.mediaType == .image && !covered.contains(asset.localIdentifier) ? asset.localIdentifier : nil
        }
    }

    /// 请求相册读写授权，并在主线程更新授权状态和后续加载流程。
    func requestAccess() {
        guard !isRunningInPreviews else { return }

        isLoading = true

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.authorizationStatus = status
                self?.isLoading = false
                self?.refreshStorageSnapshot()
                self?.fetchAssetsIfAllowed()
                self?.startColdLaunchAnalysisIfNeeded()
            }
        }
    }

    /// 每个进程冷启动至多自动触发一次分析，避免切换标签或重建视图重复扫描。
    private func startColdLaunchAnalysisIfNeeded(requiresAnalysis: Bool = true) {
        guard !isRunningInPreviews,
              authorizationStatus == .authorized || authorizationStatus == .limited,
              !Self.didStartColdLaunchAnalysis else {
            return
        }

        Self.didStartColdLaunchAnalysis = true
        if requiresAnalysis {
            startAnalysis()
        }
    }

    /// 从当前展示控制器打开系统有限相册选择器；用户更改后刷新资源。
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

    /// 打开本应用的系统设置页面，供用户调整相册授权。
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 向 PhotoKit 请求适合列表的缩略图，返回请求标识供调用方取消。
    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let cacheKey = thumbnailCacheKey(for: asset, targetSize: targetSize)
        var receivedFinalImage = false
        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
            Task { @MainActor in
                guard !isCancelled, let image, !(isDegraded && receivedFinalImage) else { return }
                if !isDegraded {
                    receivedFinalImage = true
                    let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                    self.thumbnailCache.setObject(image, forKey: asset.localIdentifier as NSString, cost: cost)
                    self.sizedThumbnailCache.setObject(image, forKey: cacheKey, cost: cost)
                }
                completion(image)
            }
        }
    }

    /// 通过资源标识查询当前相册索引。
    func asset(withIdentifier identifier: String) -> PHAsset? {
        assetsByIdentifier[identifier]
    }

    /// 读取内存中已有的缩略图；未命中时返回 nil。
    func cachedThumbnail(for identifier: String) -> UIImage? {
        thumbnailCache.object(forKey: identifier as NSString)
    }

    /// 大图必须匹配请求尺寸和资源版本，不能复用小网格或编辑前的缩略图。
    func cachedThumbnail(for identifier: String, targetSize: CGSize) -> UIImage? {
        guard let asset = assetsByIdentifier[identifier] else { return nil }
        return sizedThumbnailCache.object(forKey: thumbnailCacheKey(for: asset, targetSize: targetSize))
    }

    private func thumbnailCacheKey(for asset: PHAsset, targetSize: CGSize) -> NSString {
        let version = asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(asset.localIdentifier)|\(Int(targetSize.width))x\(Int(targetSize.height))|\(version)" as NSString
    }

    /// 对仍在资源索引中的标识汇总估算大小；优先使用精确缓存，其余使用同类校准或回退值。
    func estimatedByteCount(for assetIDs: Set<String>) -> Int64 {
        let calibration = makeMediaSizeCalibration()
        return assetIDs.reduce(Int64.zero) { total, identifier in
            guard let asset = assetsByIdentifier[identifier] else { return total }
            return total + calibratedByteCount(for: asset, calibration: calibration)
        }
    }

    /// 为一组资源共用一次校准计算；不在当前资源索引中的标识不会出现在结果中。
    func estimatedByteCounts(for assetIDs: [String]) -> [String: Int64] {
        let calibration = makeMediaSizeCalibration()
        return Dictionary(uniqueKeysWithValues: assetIDs.compactMap { id in
            assetsByIdentifier[id].map { (id, calibratedByteCount(for: $0, calibration: calibration)) }
        })
    }

    /// 优先使用缓存名称，否则读取资源元数据并缓存展示名称。
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

    /// 返回单个资源的精确或估算大小；资源不在当前索引时返回零。
    func estimatedByteCount(for assetID: String) -> Int64 {
        if let exact = exactByteCountsByIdentifier[assetID] { return exact }
        guard let asset = assetsByIdentifier[assetID] else { return 0 }
        return calibratedByteCount(for: asset, calibration: makeMediaSizeCalibration())
    }

    /// 只查询已完成的精确大小缓存，不触发资源读取。
    func exactByteCount(for assetID: String) -> Int64? {
        exactByteCountsByIdentifier[assetID]
    }

    /// 查询本次运行中被标记为不可用的资源；CancellationError 不会触发该标记。
    func isExactByteCountUnavailable(for assetID: String) -> Bool {
        unavailableByteCountIdentifiers.contains(assetID)
    }

    /// 将尚未缓存、未标记为不可用且未排队的资源加入队列；重复请求不会启动重复读取。
    /// 实际读取可能访问 iCloud，等待项较多时切换为适合长队列的结构。
    func requestExactByteCount(for assetID: String) {
        guard exactByteCountsByIdentifier[assetID] == nil,
              !unavailableByteCountIdentifiers.contains(assetID),
              byteCountTasks[assetID] == nil,
              !pendingByteCountIdentifierSet.contains(assetID),
              assetsByIdentifier[assetID] != nil else { return }

        if longPendingByteCountIdentifiers != nil {
            longPendingByteCountIdentifiers?.append(assetID)
        } else {
            pendingByteCountIdentifiers.append(assetID)
            if pendingByteCountIdentifiers.count >= 1_000 {
                var queue = MediaSizeRequestQueue()
                for identifier in pendingByteCountIdentifiers { queue.append(identifier) }
                longPendingByteCountIdentifiers = queue
                pendingByteCountIdentifiers.removeAll()
            }
        }
        pendingByteCountIdentifierSet.insert(assetID)
        startPendingByteCountRequests()
    }

    /// 取消未完成的精确大小读取并清空等待队列，避免页面离开后继续消耗资源。
    func cancelExactByteCountRequests() {
        pendingByteCountIdentifiers.removeAll()
        longPendingByteCountIdentifiers = nil
        pendingByteCountIdentifierSet.removeAll()
        byteCountTasks.values.forEach { $0.cancel() }
        byteCountTasks.removeAll()
    }

    /// 在并发上限内调度资源读取，成功后更新精确大小并合并保存与汇总计算。
    /// CancellationError 不记录为失败；其他读取错误标记为不可用，随后继续调度等待项。
    private func startPendingByteCountRequests() {
        while byteCountTasks.count < maximumConcurrentByteCountRequests {
            let assetID: String
            if let identifier = longPendingByteCountIdentifiers?.popFirst() {
                assetID = identifier
                if longPendingByteCountIdentifiers?.isEmpty == true {
                    longPendingByteCountIdentifiers = nil
                }
            } else if !pendingByteCountIdentifiers.isEmpty {
                assetID = pendingByteCountIdentifiers.removeFirst()
            } else {
                break
            }
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

    /// 选取展示项所需的资源，避免重复计入编辑前后版本；实况照片还包括配对视频。
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

    /// 按给定类型优先级返回第一个匹配资源，不读取资源内容。
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

    /// 为当前索引中存在的资源预热指定尺寸的缩略图缓存，不允许网络下载。
    func startCachingThumbnails(for assetIDs: ArraySlice<String>, targetSize: CGSize) {
        let assets = assetIDs.compactMap { assetsByIdentifier[$0] }
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    /// 停止为指定资源和尺寸预热 PhotoKit 缩略图缓存。
    func stopCachingThumbnails(for assetIDs: ArraySlice<String>, targetSize: CGSize) {
        let assets = assetIDs.compactMap { assetsByIdentifier[$0] }
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }

    /// 通过 PhotoKit 请求标识取消正在进行的媒体请求。
    func cancelThumbnail(_ requestID: PHImageRequestID) {
        imageManager.cancelImageRequest(requestID)
    }

    /// 请求指定尺寸的高质量图片预览，并返回可取消的 PhotoKit 请求标识。
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

    /// 请求视频播放资源，允许 PhotoKit 根据需要从网络获取。
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

    /// 请求指定尺寸的高质量实况照片，允许从网络获取资源。
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

    /// 基于当前资源快照开始分类；回调和最终结果必须属于当前代次，避免旧任务覆盖新状态。
    func startAnalysis() {
        guard !analysisState.isAnalyzing else { return }
        guard !assets.isEmpty else {
            analysisState = .empty
            return
        }

        let assetsToAnalyze = assets
        analysisGeneration &+= 1
        let generation = analysisGeneration
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
                startSceneAnalysis(result: result)
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

    /// 推进分析代次并取消任务，让迟到的进度与结果失效。
    func cancelAnalysis() {
        guard analysisState.isAnalyzing else { return }
        analysisGeneration &+= 1
        analysisTask?.cancel()
        analysisTask = nil
        analysisState = .cancelled
    }

    /// 删除前重新确认权限和全部资源仍可用；仅在 PhotoKit 提交成功后更新资源、分析与大小缓存。
    @discardableResult
    func deleteAssets(withIDs assetIDs: Set<String>) async -> Bool {
        guard !deletionState.isDeleting else { return false }
        guard !assetIDs.isEmpty else {
            deletionState = .failure(.noItemsSelected)
            return false
        }
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            deletionState = .failure(.photoAccessUnavailable)
            return false
        }

        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: Array(assetIDs),
            options: nil
        )
        // PhotoKit 可能在确认前移除部分资源；禁止把剩余资源静默当作完整批次删除。
        guard fetchResult.count == assetIDs.count else {
            deletionState = .failure(.itemsUnavailable)
            return false
        }

        let deletedIDs = Set((0..<fetchResult.count).map { fetchResult.object(at: $0).localIdentifier })
        let estimatedBytes = estimatedByteCount(for: deletedIDs)
        deletionState = .deleting(itemCount: fetchResult.count)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }
            sceneGeneration &+= 1
            sceneTask?.cancel()
            cityPhotoIDs.removeAll { deletedIDs.contains($0) }
            assets.removeAll { deletedIDs.contains($0.localIdentifier) }
            deletedIDs.forEach { exactByteCountsByIdentifier[$0] = nil }
            rebuildAssetIndex()
            scheduleMediaSizeIndexSave()
            updateAnalysisAfterDeleting(deletedIDs)
            if case let .success(result) = analysisState { startSceneAnalysis(result: result) }
            if case let .partialFailure(result) = analysisState { startSceneAnalysis(result: result) }
            persistAnalysisState()
            refreshStorageSnapshot()
            deletionState = .success(
                deletedCount: deletedIDs.count,
                estimatedBytes: estimatedBytes
            )
            return true
        } catch {
            let photoError = error as NSError
            if photoError.domain == PHPhotosError.errorDomain,
               photoError.code == PHPhotosError.Code.userCancelled.rawValue {
                // 取消系统确认不是失败；回到可操作状态并保留当前选择。
                deletionState = .idle
                return false
            }
            deletionState = .failure(.deletionFailed)
            return false
        }
    }

    /// 仅在没有删除操作进行时清除上次删除结果。
    func clearDeletionResult() {
        guard !deletionState.isDeleting else { return }
        deletionState = .idle
    }

    /// 授权可用时读取相册；无权限时清空资源并重建索引。
    private func fetchAssetsIfAllowed() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            assets = []
            rebuildAssetIndex()
            return
        }

        fetchAssets()
    }

    /// 按创建时间倒序取得 PhotoKit 资源并重建索引。
    private func fetchAssets() {
        let interval = MediaPerformance.begin("Media Fetch Assets")
        defer { MediaPerformance.end("Media Fetch Assets", id: interval) }
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

    /// 重建资源标识索引和资源库修订号，并移除不再存在资源的大小及名称缓存。
    private func rebuildAssetIndex() {
        calibrationRevision = nil
        let interval = MediaPerformance.begin("Media Rebuild Index")
        defer { MediaPerformance.end("Media Rebuild Index", id: interval) }
        assetsByIdentifier = Dictionary(
            uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) }
        )
        libraryRevision = Self.makeLibraryRevision(for: assets)
        exactByteCountsByIdentifier = exactByteCountsByIdentifier.filter {
            assetsByIdentifier[$0.key] != nil
        }
        recalculateLibraryByteCounts()
        displayNamesByIdentifier = displayNamesByIdentifier.filter {
            assetsByIdentifier[$0.key] != nil
        }
    }

    /// 根据最新精确大小和校准系数分别重算照片、视频的相册大小估算。
    private func recalculateLibraryByteCounts() {
        let interval = MediaPerformance.begin("Media Recalculate Sizes")
        defer { MediaPerformance.end("Media Recalculate Sizes", id: interval) }
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

    /// 优先使用精确大小；没有可用校准系数时回退到资源元数据估算。
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
        if calibrationRevision == mediaSizeRevision { return cachedCalibration }
        var samples: [String: [Double]] = [:]
        for (identifier, byteCount) in exactByteCountsByIdentifier {
            guard let asset = assetsByIdentifier[identifier] else { continue }
            let denominator = Self.calibrationDenominator(for: asset)
            guard denominator > 0 else { continue }
            samples[Self.calibrationKey(for: asset), default: []]
                .append(Double(byteCount) / denominator)
        }

        cachedCalibration = samples.compactMapValues { values in
            MediaCalibrationMedianCandidate.preferredCoefficient(values)
        }
        calibrationRevision = mediaSizeRevision
        return cachedCalibration
    }

    /// 视频按时长、图片按像素数作为大小校准基数，避免零值。
    nonisolated static func calibrationDenominator(for asset: PHAsset) -> Double {
        if asset.mediaType == .video {
            return max(asset.duration, 1)
        }
        return Double(max(asset.pixelWidth, 1)) * Double(max(asset.pixelHeight, 1))
    }

    /// 从系统类型或资源元数据取得格式标识；未知格式回退到通用数据类型。
    nonisolated static func contentTypeIdentifier(for asset: PHAsset) -> String {
        if #available(iOS 26.0, *) {
            return asset.contentType.identifier
        }
        // Resource metadata identifies the format without downloading the asset.
        let resourceType: PHAssetResourceType = asset.mediaType == .video ? .video : .photo
        return PHAssetResource.assetResources(for: asset)
            .first(where: { $0.type == resourceType })?.uniformTypeIdentifier ?? "public.data"
    }

    /// 按媒体格式、分辨率及子类型分组，避免不同资源共用不适合的估算系数。
    nonisolated static func calibrationKey(for asset: PHAsset) -> String {
        let format = contentTypeIdentifier(for: asset).lowercased()
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

    /// 仅恢复仍存在且修改日期未变的非负大小，避免复用过期结果。
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

    /// 合并短时间内的大小更新，并保存带修改日期的快照以便后续校验。
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

    /// 从成功或部分成功的分析结果中移除已删除资源，同时保留原有结果状态。
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

    /// 恢复时先剔除已不存在的资源；返回值表示资源库修订号是否匹配、结果能否直接复用。
    @discardableResult
    private func restoreAnalysis(from snapshot: MediaStateSnapshot?) -> Bool {
        guard let snapshot else {
            if analysisState.isAnalyzing { analysisState = .cancelled }
            return false
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
        return snapshot.libraryRevision == libraryRevision
    }

    /// 持久化完整或部分分析结果及相册修订号；其他状态保存空快照。
    private func persistAnalysisState() {
        let snapshot: MediaStateSnapshot?
        switch analysisState {
        case .success(let result):
            snapshot = MediaStateSnapshot(
                result: result,
                isPartial: false,
                libraryRevision: libraryRevision
            )
        case .partialFailure(let result):
            snapshot = MediaStateSnapshot(
                result: result,
                isPartial: true,
                libraryRevision: libraryRevision
            )
        default:
            snapshot = nil
        }
        Task { await stateStore.saveMediaState(snapshot) }
    }

    /// PhotoKit identifiers are stable for an asset. Mixing the metadata that affects
    /// classification makes additions, removals, edits, and subtype changes invalidate
    /// the cached analysis while keeping the persisted revision constant across launches.
    private static func makeLibraryRevision(for assets: [PHAsset]) -> MediaLibraryRevision {
        var fingerprint: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        @inline(__always)
        /// 按字节混入数值元数据，生成稳定的相册修订指纹。
        func mix(_ value: UInt64, into fingerprint: inout UInt64) {
            var remaining = value
            for _ in 0 ..< MemoryLayout<UInt64>.size {
                fingerprint ^= remaining & 0xff
                fingerprint &*= prime
                remaining >>= 8
            }
        }

        // PhotoKit may return equal-date assets in a different order after reboot.
        // Inventory identity must not depend on that display ordering.
        for asset in assets.sorted(by: { $0.localIdentifier < $1.localIdentifier }) {
            for byte in asset.localIdentifier.utf8 {
                fingerprint ^= UInt64(byte)
                fingerprint &*= prime
            }
            // Separate adjacent identifiers so concatenated values cannot alias.
            fingerprint ^= 0xff
            fingerprint &*= prime
            mix(asset.modificationDate?.timeIntervalSinceReferenceDate.bitPattern ?? 0, into: &fingerprint)
            mix(asset.creationDate?.timeIntervalSinceReferenceDate.bitPattern ?? 0, into: &fingerprint)
            mix(UInt64(UInt32(bitPattern: Int32(asset.pixelWidth))), into: &fingerprint)
            mix(UInt64(UInt32(bitPattern: Int32(asset.pixelHeight))), into: &fingerprint)
            mix(UInt64(asset.mediaType.rawValue), into: &fingerprint)
            mix(UInt64(asset.mediaSubtypes.rawValue), into: &fingerprint)
        }

        return MediaLibraryRevision(assetCount: assets.count, fingerprint: fingerprint)
    }

    /// Capacity queries can be temporarily unavailable after reboot. Keep the last
    /// successful value and retry without blocking the UI or duplicating requests.
    private func refreshStorageSnapshot() {
        guard !isRunningInPreviews, storageSnapshotTask == nil else { return }
        storageSnapshotTask = Task { [weak self] in
            defer { self?.storageSnapshotTask = nil }
            for attempt in 0..<3 {
                guard !Task.isCancelled else { return }
                if attempt > 0 {
                    do {
                        try await Task.sleep(for: .milliseconds(500 * attempt))
                    } catch { return }
                }
                let storage = await Task.detached(priority: .utility) {
                    Self.loadStorageSnapshot()
                }.value
                guard !Task.isCancelled else { return }
                if let storage {
                    self?.storageSnapshot = storage
                    return
                }
            }
        }
    }

    /// Read from the existing sandbox root; Documents may not have been created yet.
    nonisolated private static func loadStorageSnapshot() -> DeviceStorageSnapshot? {
        let baseURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let values = try? baseURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        if let total = values?.volumeTotalCapacity, total > 0,
           let available = values?.volumeAvailableCapacityForImportantUsage
                ?? values?.volumeAvailableCapacity.map({ Int64($0) }) {
            return DeviceStorageSnapshot(
                totalBytes: Int64(total), availableBytes: min(max(0, available), Int64(total))
            )
        }
        // Some volumes do not provide the important-usage estimate. The standard
        // filesystem attributes still provide real capacity values for the chart.
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: baseURL.path),
              let total = (attributes[.systemSize] as? NSNumber)?.int64Value, total > 0,
              let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else { return nil }
        return DeviceStorageSnapshot(
            totalBytes: total, availableBytes: min(max(0, available), total)
        )
    }

    /// 精确大小和校准不可用时，依据视频分辨率、时长或图片像素等元数据估算大小。
    nonisolated static func fallbackEstimatedByteCount(for asset: PHAsset) -> Int64 {
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

        let format = contentTypeIdentifier(for: asset).lowercased()
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

/// 逐块累计 PhotoKit 资源字节数，不将完整照片或视频保留在内存中。
private enum MediaAssetResourceByteCounter {
    /// 顺序累计所选资源；没有可读资源或任一读取失败时抛出错误。
    static func byteCount(for resources: [PHAssetResource]) async throws -> Int64 {
        guard !resources.isEmpty else { throw MediaAssetResourceByteCountError.noResources }
        var total: Int64 = 0
        for resource in resources {
            try Task.checkCancellation()
            total += try await byteCount(for: resource)
        }
        return total
    }

    /// 允许 PhotoKit 通过网络获取资源；任务取消时同时取消底层数据请求。
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

/// 无可计数资源时使用的内部错误。
private enum MediaAssetResourceByteCountError: Error {
    case noResources
}

/// 用锁保护 PhotoKit 回调中的累计字节数，避免跨回调共享可变状态发生竞争。
private final class MediaAssetResourceByteAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var byteCount: Int64 = 0

    /// 在锁保护下累加一段资源回调的字节数。
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

/// 协调请求标识注册与取消的先后顺序，处理取消先于 PhotoKit 返回标识的情况。
private final class MediaAssetResourceRequestToken: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var requestID: PHAssetResourceDataRequestID?
    nonisolated(unsafe) private weak var manager: PHAssetResourceManager?
    nonisolated(unsafe) private var isCancelled = false

    /// 保存请求标识；若此前已取消，注册后立即取消该请求。
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

    /// 记录取消并取消已注册的请求；尚未注册时由后续注册路径补做。
    nonisolated func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        let manager = manager
        lock.unlock()
        if let requestID { manager?.cancelDataRequest(requestID) }
    }
}
