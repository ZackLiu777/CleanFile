//
//  媒体分类与相似图片分析
//
//  分类视频及截图，并通过缩略图感知哈希筛选候选，再用 Vision 特征比较。
//  缩略图和 Vision 请求分别限制并发；失败项目计入跳过数量，分析不删除资源。
//

//
//  文件职责：封装 MediaClassification 领域服务及其边界处理。
//  所属模块：CleanMyIPhone。
//

import CoreGraphics
import Foundation
import Photos
import UIKit
import Vision

@MainActor
/// 协调媒体元数据分类及相似图片分析；哈希用于筛选候选，最终相似判断还需 Vision 比较。
struct MediaClassificationService {
    typealias ProgressHandler = @MainActor @Sendable (MediaAnalysisProgress) -> Void

    /// 轻量哈希只处理 64×64 缩略图，可以用略高的有界并发缩短相册读取时间。
    private let maximumConcurrentHashRequests = 4
    /// Vision 特征生成仍属于 CPU 密集任务，限制为两路以避免扫描时挤占 UI 和内存。
    private let maximumConcurrentVisionRequests = 2
    nonisolated private static let maximumPerceptualHashDistance = 16
    nonisolated private static let maximumHashMatchesPerImage = 32
    // Vision has no universal distance threshold. Start conservatively and
    // calibrate this value against representative user photo libraries.
    private let maximumFeaturePrintDistance: Float = 0.55
    private let imageManager = PHCachingImageManager()
    private let featureEngine = VisionFeatureEngine()

    /// 分类视频、截图和 Live Photo，分阶段生成图片哈希、候选对及 Vision 特征，最终保守分组。
    /// 支持进度回调与取消；单张资源不可用时计入跳过，不触发删除。
    func analyze(
        assets: [PHAsset],
        progress: ProgressHandler
    ) async throws -> MediaClassificationResult {
        try Task.checkCancellation()
        progress(MediaAnalysisProgress(phase: .discovering, completed: 0, total: assets.count))

        let videos = assets.filter { $0.mediaType == .video }.map(Self.classifyVideo)
        let images = assets.filter { $0.mediaType == .image }
        let screenshotIDs = images
            .filter { $0.mediaSubtypes.contains(.photoScreenshot) }
            .map(\.localIdentifier)
        let livePhotoIDs = images
            .filter { $0.mediaSubtypes.contains(.photoLive) }
            .map(\.localIdentifier)
        let candidates = similarityCandidates(from: images)
        let assetsByIdentifier = Dictionary(
            uniqueKeysWithValues: images.map { ($0.localIdentifier, $0) }
        )
        await featureEngine.retainFeatures(for: Set(candidates.map(\.id)))

        progress(MediaAnalysisProgress(
            phase: .generatingFeatures,
            completed: 0,
            total: candidates.count
        ))
        let hashOutcomes = await generateHashes(
            for: candidates,
            assetsByIdentifier: assetsByIdentifier,
            progress: progress
        )
        try Task.checkCancellation()

        await featureEngine.persistHashes()
        try Task.checkCancellation()

        let availableHashes = hashOutcomes.compactMap(\.feature)
        let hashSkippedCount = hashOutcomes.count - availableHashes.count
        // 哈希索引在大图库中属于 CPU 密集工作，不能继承 MediaClassificationService
        // 的 MainActor 隔离，否则十万级资源会长时间阻塞滚动和进度动画。
        let candidateSearch = await Task.detached(priority: .utility) {
            Self.candidatePairs(from: availableHashes)
        }.value
        let comparisonPairs = candidateSearch.pairs
        var comparisonIdentifiers = Set<String>()
        comparisonIdentifiers.reserveCapacity(min(candidates.count, comparisonPairs.count * 2))
        for pair in comparisonPairs {
            comparisonIdentifiers.insert(candidateSearch.features[Int(pair.firstIndex)].id)
            comparisonIdentifiers.insert(candidateSearch.features[Int(pair.secondIndex)].id)
        }
        let comparisonCandidates = candidates.filter { comparisonIdentifiers.contains($0.id) }
        let comparisonWorkCount = comparisonCandidates.count + comparisonPairs.count
        progress(MediaAnalysisProgress(
            phase: .comparingImages,
            completed: 0,
            total: candidates.count
        ))

        // Vision 是扫描中最昂贵的一步。只有通过感知哈希初筛的图片才生成
        // Feature Print，普通且没有相似候选的照片不会再承担这部分成本。
        let visionSkippedCount = await generateVisionFeatures(
            for: comparisonCandidates,
            assetsByIdentifier: assetsByIdentifier
        ) { completed in
            progress(MediaAnalysisProgress(
                phase: .comparingImages,
                completed: Self.displayProgress(
                    completedWork: completed,
                    totalWork: comparisonWorkCount,
                    imageCount: candidates.count
                ),
                total: candidates.count
            ))
        }
        try Task.checkCancellation()

        var acceptedPairs: [AcceptedPair] = []
        let comparisonBatchSize = 128
        for batchStart in stride(from: 0, to: comparisonPairs.count, by: comparisonBatchSize) {
            try Task.checkCancellation()
            let batchEnd = min(batchStart + comparisonBatchSize, comparisonPairs.count)
            let batch = comparisonPairs[batchStart ..< batchEnd].map { pair in
                CandidatePair(
                    firstID: candidateSearch.features[Int(pair.firstIndex)].id,
                    secondID: candidateSearch.features[Int(pair.secondIndex)].id
                )
            }
            if let matches = try? await featureEngine.acceptedPairs(
                from: batch,
                maximumDistance: maximumFeaturePrintDistance
            ) {
                acceptedPairs.append(contentsOf: matches)
            }
            progress(MediaAnalysisProgress(
                phase: .comparingImages,
                completed: Self.displayProgress(
                    completedWork: comparisonCandidates.count + batchEnd,
                    totalWork: comparisonWorkCount,
                    imageCount: candidates.count
                ),
                total: candidates.count
            ))
        }

        return MediaClassificationResult(
            similarImageGroups: makeConservativeGroups(
                from: acceptedPairs,
                candidates: candidates
            ),
            classifiedVideos: videos,
            screenshotIDs: screenshotIDs,
            livePhotoIDs: livePhotoIDs,
            skippedImageCount: hashSkippedCount + visionSkippedCount
        )
    }

    /// 根据时长、分辨率与 PhotoKit 子类型计算视频标签；一个视频可同时属于多个分类。
    /// 长视频阈值为十分钟，4K 标签以像素长边至少 3840 为准。
    nonisolated static func categories(
        duration: TimeInterval,
        pixelWidth: Int,
        pixelHeight: Int,
        mediaSubtypes: PHAssetMediaSubtype
    ) -> Set<VideoCategory> {
        var categories = Set<VideoCategory>()
        if duration >= 10 * 60 { categories.insert(.longDuration) }
        if max(pixelWidth, pixelHeight) >= 3_840 { categories.insert(.fourK) }
        if mediaSubtypes.contains(.videoScreenRecording) { categories.insert(.screenRecording) }
        if mediaSubtypes.contains(.videoHighFrameRate) { categories.insert(.slowMotion) }
        if mediaSubtypes.contains(.videoTimelapse) { categories.insert(.timeLapse) }
        return categories
    }

    /// 从 PhotoKit 资源提取视频元数据和全部适用标签。
    private static func classifyVideo(_ asset: PHAsset) -> ClassifiedVideo {
        ClassifiedVideo(
            id: asset.localIdentifier,
            duration: asset.duration,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            categories: categories(
                duration: asset.duration,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                mediaSubtypes: asset.mediaSubtypes
            )
        )
    }

    /// 提取相似分析需要的标识、尺寸和日期，并用修改时间及尺寸构建缓存键。
    private func similarityCandidates(from assets: [PHAsset]) -> [SimilarityCandidate] {
        assets.map { asset in
            SimilarityCandidate(
                id: asset.localIdentifier,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                creationDate: asset.creationDate,
                cacheKey: FeatureCacheKey(
                    modificationDate: asset.modificationDate,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight
                )
            )
        }
    }

    /// 为全相册生成低成本感知哈希，先完成候选召回而不执行昂贵的 Vision 分析。
    private func generateHashes(
        for candidates: [SimilarityCandidate],
        assetsByIdentifier: [String: PHAsset],
        progress: ProgressHandler
    ) async -> [FeatureOutcome] {
        guard !candidates.isEmpty else { return [] }
        var outcomes: [FeatureOutcome] = []
        // Restore every reusable result before scheduling cold PhotoKit requests.
        // Otherwise four new/iCloud-backed assets at the front can hold all cached
        // assets behind them and leave the displayed count at zero.
        let cached = await featureEngine.cachedHashes(for: candidates)
        var pending: [SimilarityCandidate] = []
        for candidate in candidates {
            if let hash = cached[candidate.id] {
                outcomes.append(FeatureOutcome(feature: CandidateFeature(
                    id: candidate.id, perceptualHash: hash
                )))
            } else {
                pending.append(candidate)
            }
        }
        progress(MediaAnalysisProgress(
            phase: .generatingFeatures, completed: outcomes.count, total: candidates.count
        ))
        guard !pending.isEmpty, !Task.isCancelled else { return outcomes }
        var nextIndex = 0

        await withTaskGroup(of: FeatureOutcome.self) { group in
            let initialCount = min(maximumConcurrentHashRequests, pending.count)
            for _ in 0 ..< initialCount {
                let candidate = pending[nextIndex]
                let asset = assetsByIdentifier[candidate.id]
                group.addTask { @MainActor in
                    await generateHash(for: candidate, asset: asset)
                }
                nextIndex += 1
            }

            while let outcome = await group.next() {
                outcomes.append(outcome)
                if Self.shouldReportProgress(completed: outcomes.count, total: candidates.count) {
                    progress(MediaAnalysisProgress(
                        phase: .generatingFeatures,
                        completed: outcomes.count,
                        total: candidates.count
                    ))
                }
                if Task.isCancelled {
                    group.cancelAll()
                } else if nextIndex < pending.count {
                    let candidate = pending[nextIndex]
                    let asset = assetsByIdentifier[candidate.id]
                    group.addTask { @MainActor in
                        await generateHash(for: candidate, asset: asset)
                    }
                    nextIndex += 1
                }
            }
        }
        return outcomes
    }

    /// 读取一张低分辨率缩略图并生成 dHash；缓存命中时完全跳过图片请求。
    private func generateHash(
        for candidate: SimilarityCandidate,
        asset: PHAsset?
    ) async -> FeatureOutcome {
        guard !Task.isCancelled, let asset else {
            return FeatureOutcome(feature: nil)
        }

        do {
            if let hash = await featureEngine.cachedHash(
                id: candidate.id,
                cacheKey: candidate.cacheKey
            ) {
                return FeatureOutcome(feature: CandidateFeature(
                    id: candidate.id,
                    perceptualHash: hash
                ))
            }
            let image = try await requestThumbnail(for: asset, targetPixelSize: 64)
            let hash = try await featureEngine.storeHash(
                id: candidate.id,
                cacheKey: candidate.cacheKey,
                image: image
            )
            return FeatureOutcome(feature: CandidateFeature(
                id: candidate.id,
                perceptualHash: hash
            ))
        } catch {
            return FeatureOutcome(feature: nil)
        }
    }

    /// 仅为哈希命中的候选图片生成 Vision Feature Print，并以有界并发控制资源占用。
    private func generateVisionFeatures(
        for candidates: [SimilarityCandidate],
        assetsByIdentifier: [String: PHAsset],
        progress: @MainActor @Sendable (Int) -> Void
    ) async -> Int {
        guard !candidates.isEmpty else { return 0 }
        var completed = 0
        var skipped = 0
        var nextIndex = 0

        await withTaskGroup(of: Bool.self) { group in
            let initialCount = min(maximumConcurrentVisionRequests, candidates.count)
            for _ in 0 ..< initialCount {
                let candidate = candidates[nextIndex]
                let asset = assetsByIdentifier[candidate.id]
                group.addTask { @MainActor in
                    await generateVisionFeature(for: candidate, asset: asset)
                }
                nextIndex += 1
            }

            while let succeeded = await group.next() {
                completed += 1
                if !succeeded { skipped += 1 }
                if Self.shouldReportProgress(completed: completed, total: candidates.count) {
                    progress(completed)
                }
                if Task.isCancelled {
                    group.cancelAll()
                } else if nextIndex < candidates.count {
                    let candidate = candidates[nextIndex]
                    let asset = assetsByIdentifier[candidate.id]
                    group.addTask { @MainActor in
                        await generateVisionFeature(for: candidate, asset: asset)
                    }
                    nextIndex += 1
                }
            }
        }
        return skipped
    }

    /// 为单个候选生成 Vision 特征；已有同版本缓存时不再请求 Photos 缩略图。
    private func generateVisionFeature(
        for candidate: SimilarityCandidate,
        asset: PHAsset?
    ) async -> Bool {
        guard !Task.isCancelled, let asset else { return false }
        if await featureEngine.hasObservation(id: candidate.id, cacheKey: candidate.cacheKey) {
            return true
        }

        do {
            let image = try await requestThumbnail(for: asset, targetPixelSize: 256)
            try await featureEngine.storeObservation(
                id: candidate.id,
                cacheKey: candidate.cacheKey,
                image: image
            )
            return true
        } catch {
            // 单张资源可能位于尚未下载的 iCloud、已被删除或暂时不可读。
            // 跳过该候选可保证其余本地资源继续完成扫描。
            return false
        }
    }

    /// 按扫描阶段请求恰好够用的缩略图，避免轻量哈希阶段解码 256×256 图片。
    /// 禁止为此请求联网下载；资源不可用时返回错误，取消会转发给 PhotoKit。
    private func requestThumbnail(
        for asset: PHAsset,
        targetPixelSize: CGFloat
    ) async throws -> CGImage {
        let controller = ImageRequestController(manager: imageManager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = ContinuationGate<CGImage>(continuation: continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = false

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: targetPixelSize, height: targetPixelSize),
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        gate.resume(throwing: error)
                    } else if (info?[PHImageCancelledKey] as? Bool) == true {
                        gate.resume(throwing: CancellationError())
                    } else if let cgImage = image?.cgImage {
                        gate.resume(returning: cgImage)
                    } else {
                        gate.resume(throwing: MediaAnalysisError.unexpected)
                    }
                }
                controller.store(requestID)
            }
        } onCancel: {
            controller.cancel()
        }
    }

    /// 按总工作量约百分之一的间隔节流进度，同时保证最后一次更新可报告。
    nonisolated static func shouldReportProgress(completed: Int, total: Int) -> Bool {
        guard total > 0 else { return true }
        let interval = max(1, total / 100)
        return completed == total || completed.isMultiple(of: interval)
    }

    /// 将候选特征和图片对组成的内部工作量映射为真实图片计数，避免 UI 总数虚增。
    nonisolated static func displayProgress(
        completedWork: Int,
        totalWork: Int,
        imageCount: Int
    ) -> Int {
        guard imageCount > 0 else { return 0 }
        guard totalWork > 0 else { return imageCount }
        let fraction = Double(min(max(completedWork, 0), totalWork)) / Double(totalWork)
        return min(imageCount, Int((fraction * Double(imageCount)).rounded(.down)))
    }

    /// 稳定排序哈希后构建分段汉明距离索引；大图库限制每张图片的比较工作量。
    nonisolated private static func candidatePairs(from features: [CandidateFeature]) -> CandidateSearchResult {
        let orderedFeatures = features.sorted(by: { $0.id < $1.id })
        let index = SegmentedHammingIndex(features: orderedFeatures, pruneDenseBuckets: true)
        let evaluationLimit = orderedFeatures.count >= 500_000 ? 4_096 : Int.max
        let pairs = index.allPairs(
            maximumDistance: maximumPerceptualHashDistance,
            maximumResults: maximumHashMatchesPerImage,
            maximumEvaluationsPerImage: evaluationLimit,
            workerCount: min(4, ProcessInfo.processInfo.activeProcessorCount)
        )
        return CandidateSearchResult(features: orderedFeatures, pairs: pairs)
    }

    /// 按距离由近到远构建相似组，仅把与组首匹配的资源加入已有组。
    /// 不通过 A 相似 B、B 相似 C 推断 A 相似 C，以免扩大建议删除范围。
    private func makeConservativeGroups(
        from pairs: [AcceptedPair],
        candidates: [SimilarityCandidate]
    ) -> [SimilarImageGroup] {
        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var clusters: [[String]] = []
        var clusterIndexByID: [String: Int] = [:]

        for pair in pairs.sorted(by: { $0.distance < $1.distance }) {
            let firstCluster = clusterIndexByID[pair.firstID]
            let secondCluster = clusterIndexByID[pair.secondID]
            switch (firstCluster, secondCluster) {
            case (nil, nil):
                guard let first = candidatesByID[pair.firstID],
                      let second = candidatesByID[pair.secondID] else { continue }
                let ordered = [first, second].sorted(by: Self.preferredKeeperOrder).map(\.id)
                let index = clusters.count
                clusters.append(ordered)
                ordered.forEach { clusterIndexByID[$0] = index }
            case let (.some(index), nil):
                guard clusters[index].first == pair.firstID else { continue }
                clusters[index].append(pair.secondID)
                clusterIndexByID[pair.secondID] = index
            case let (nil, .some(index)):
                guard clusters[index].first == pair.secondID else { continue }
                clusters[index].append(pair.firstID)
                clusterIndexByID[pair.firstID] = index
            case let (.some(first), .some(second)) where first == second:
                continue
            default:
                // Avoid transitive A≈B≈C merging when A and C weren't accepted.
                continue
            }
        }

        return clusters.compactMap { ids in
            let items = ids.compactMap { id -> SimilarImageItem? in
                guard let candidate = candidatesByID[id] else { return nil }
                return SimilarImageItem(
                    id: candidate.id,
                    pixelWidth: candidate.pixelWidth,
                    pixelHeight: candidate.pixelHeight,
                    creationDate: candidate.creationDate
                )
            }
            guard let keeper = items.first, items.count > 1 else { return nil }
            return SimilarImageGroup(id: keeper.id, items: items, suggestedKeeperID: keeper.id)
        }
    }

    /// 优先保留像素更多的图片，再按创建日期及标识稳定排序。
    private static func preferredKeeperOrder(
        _ lhs: SimilarityCandidate,
        _ rhs: SimilarityCandidate
    ) -> Bool {
        let lhsPixels = lhs.pixelWidth * lhs.pixelHeight
        let rhsPixels = rhs.pixelWidth * rhs.pixelHeight
        if lhsPixels != rhsPixels { return lhsPixels > rhsPixels }
        switch (lhs.creationDate, rhs.creationDate) {
        case let (.some(lhsDate), .some(rhsDate)) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.id < rhs.id
        }
    }
}

/// 相似度分析所需的资源标识、尺寸、创建时间和特征缓存键。
private struct SimilarityCandidate: Sendable {
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let cacheKey: FeatureCacheKey
}

/// 通过修改时间和像素尺寸判断已缓存特征是否仍适用于当前资源。
nonisolated struct FeatureCacheKey: Codable, Hashable, Sendable {
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

/// 一张候选图片的标识和 64 位感知哈希。
nonisolated struct CandidateFeature: Sendable {
    let id: String
    let perceptualHash: UInt64
}

/// 哈希生成结果；特征为 nil 时表示该候选未获得可用特征。
private struct FeatureOutcome: Sendable { let feature: CandidateFeature? }
/// 以有序特征数组下标表示候选对，避免在搜索过程中反复保存标识字符串。
nonisolated struct IndexedCandidatePair: Sendable {
    let firstIndex: Int32
    let secondIndex: Int32
}
/// 成对保存排序后的特征和引用该数组的候选索引。
nonisolated private struct CandidateSearchResult: Sendable {
    let features: [CandidateFeature]
    let pairs: [IndexedCandidatePair]
}
/// 用资源标识表示待进一步比较的图片对。
private struct CandidatePair: Sendable { let firstID: String; let secondID: String }
/// 记录通过比较的图片对及 Vision 特征距离，供后续分组排序使用。
private struct AcceptedPair: Sendable { let firstID: String; let secondID: String; let distance: Float }

/// 用多个重叠的 16 位分段建立倒排索引，再以完整 64 位汉明距离复核候选。
///
/// BK-tree 在 64 位哈希和较宽搜索半径下会访问大部分节点，十万级数据会退化为
/// 接近平方复杂度。分段索引通过固定数量的桶查找缩小候选范围；距离不超过 8
/// 的哈希必然至少有一个分段相差不超过 2 位。实际结果仍受每张图片的比较次数
/// 和结果数量上限影响，达到上限时不保证返回所有满足距离条件的图片对。
nonisolated final class SegmentedHammingIndex: @unchecked Sendable {
    private static let bandOffsets = [0, 16, 32, 48, 8, 24, 40, 56]
    private static let probeMasks: [UInt16] = {
        var masks: [UInt16] = [0]
        masks.reserveCapacity(137)
        for first in 0 ..< 16 {
            masks.append(UInt16(1) << first)
        }
        for first in 0 ..< 16 {
            for second in (first + 1) ..< 16 {
                masks.append((UInt16(1) << first) | (UInt16(1) << second))
            }
        }
        return masks
    }()

    private let features: [CandidateFeature]
    /// 8 × 65,536 的键空间是固定的；连续数组避免每次探测都执行 Dictionary 哈希。
    private let buckets: [[Int32]]
    private let pruneDenseBuckets: Bool

    /// 为每个特征建立八组分段桶；桶内下标按输入顺序递增，供密集桶剪枝使用。
    init(features: [CandidateFeature], pruneDenseBuckets: Bool = false) {
        self.pruneDenseBuckets = pruneDenseBuckets
        self.features = features
        var builtBuckets = [[Int32]](repeating: [], count: 8 * (1 << 16))
        for (featureIndex, feature) in features.enumerated() {
            for (band, offset) in Self.bandOffsets.enumerated() {
                let value = Self.bandValue(of: feature.perceptualHash, offset: offset)
                builtBuckets[Self.bucketIndex(band: band, value: value)].append(Int32(featureIndex))
            }
        }
        buckets = builtBuckets
    }

    /// 将查询范围分配给有限数量的工作线程，分别去重、筛选并汇总候选对。
    /// 每张图片仅与较早的索引配对；比较次数和返回数量均受参数限制。
    /// 线程完成顺序可能不同，因此返回数组不保证按查询顺序排列。
    func allPairs(
        maximumDistance: Int,
        maximumResults: Int,
        maximumEvaluationsPerImage: Int,
        workerCount: Int
    ) -> [IndexedCandidatePair] {
        guard maximumResults > 0, features.count > 1 else { return [] }
        let workers = max(1, min(workerCount, features.count))
        let resultLock = NSLock()
        var combined: [IndexedCandidatePair] = []

        DispatchQueue.concurrentPerform(iterations: workers) { worker in
            var visited = [UInt32](repeating: 0, count: features.count)
            var generation: UInt32 = 0
            var localPairs: [IndexedCandidatePair] = []
            let lowerBound = features.count * worker / workers
            let upperBound = features.count * (worker + 1) / workers

            for queryIndex in lowerBound ..< upperBound {
                generation &+= 1
                let matches = matches(
                    queryIndex: queryIndex,
                    maximumDistance: maximumDistance,
                    maximumResults: maximumResults,
                    maximumEvaluations: maximumEvaluationsPerImage,
                    visited: &visited,
                    generation: generation
                )
                localPairs.append(contentsOf: matches.map {
                    IndexedCandidatePair(firstIndex: $0.index, secondIndex: Int32(queryIndex))
                })
            }

            resultLock.withLock {
                combined.append(contentsOf: localPairs)
            }
        }
        return combined
    }

    /// 查询指定图片与先前图片的候选距离，在密集桶中启用提前退出优化。
    /// 使用代次标记避免跨多个桶重复评估；距离合格的结果按上限保留。
    /// 达到比较上限后停止搜索，因此最近结果仅针对已评估候选。
    private func matches(
        queryIndex: Int,
        maximumDistance: Int,
        maximumResults: Int,
        maximumEvaluations: Int,
        visited: inout [UInt32],
        generation: UInt32
    ) -> [(index: Int32, distance: Int)] {
        // Sparse queries keep the original hot loop; pruning is useful only for a dense first bucket.
        guard pruneDenseBuckets,
              buckets[Self.bucketIndex(band: 0, value: Self.bandValue(of: features[queryIndex].perceptualHash, offset: 0))].count >= 128 else {
            return originalMatches(queryIndex: queryIndex, maximumDistance: maximumDistance,
                                   maximumResults: maximumResults, maximumEvaluations: maximumEvaluations,
                                   visited: &visited, generation: generation)
        }
        let hash = features[queryIndex].perceptualHash
        let bandValues = Self.bandOffsets.map { Self.bandValue(of: hash, offset: $0) }
        var matches: [(index: Int32, distance: Int)] = []
        matches.reserveCapacity(maximumResults)
        var evaluated = 0

        search: for mask in Self.probeMasks {
            for band in Self.bandOffsets.indices {
                let indices = buckets[
                    Self.bucketIndex(band: band, value: bandValues[band] ^ mask)
                ]
                for rawIndex in indices {
                    let index = Int(rawIndex)
                    // Buckets are appended in index order: the remaining suffix cannot be a prior asset.
                    if pruneDenseBuckets, index >= queryIndex { break }
                    guard index < queryIndex, visited[index] != generation else { continue }
                    visited[index] = generation
                    evaluated += 1
                    let distance = (features[index].perceptualHash ^ hash).nonzeroBitCount
                    if distance <= maximumDistance {
                        Self.retainNearest(
                            (rawIndex, distance),
                            in: &matches,
                            maximumResults: maximumResults
                        )
                    }
                    // All zero-distance hashes occur in the first exact bucket. Once full,
                    // its ascending traversal has already found the globally preferred zero matches.
                    if pruneDenseBuckets, mask == 0, band == 0,
                       matches.count == maximumResults, matches.last?.distance == 0 {
                        break search
                    }
                    if evaluated >= maximumEvaluations { break search }
                }
            }
        }
        matches.sort { Self.isPreferred($0, over: $1) }
        return matches
    }

    /// 稀疏桶或未启用剪枝时的基线搜索，按相同距离和数量规则筛选。
    /// 只处理当前查询之前且本轮尚未访问的索引，避免重复配对。
    private func originalMatches(
        queryIndex: Int,
        maximumDistance: Int,
        maximumResults: Int,
        maximumEvaluations: Int,
        visited: inout [UInt32],
        generation: UInt32
    ) -> [(index: Int32, distance: Int)] {
        let hash = features[queryIndex].perceptualHash
        let bandValues = Self.bandOffsets.map { Self.bandValue(of: hash, offset: $0) }
        var matches: [(index: Int32, distance: Int)] = []
        matches.reserveCapacity(maximumResults)
        var evaluated = 0

        search: for mask in Self.probeMasks {
            for band in Self.bandOffsets.indices {
                let indices = buckets[
                    Self.bucketIndex(band: band, value: bandValues[band] ^ mask)
                ]
                for rawIndex in indices {
                    let index = Int(rawIndex)
                    guard index < queryIndex, visited[index] != generation else { continue }
                    visited[index] = generation
                    evaluated += 1
                    let distance = (features[index].perceptualHash ^ hash).nonzeroBitCount
                    if distance <= maximumDistance {
                        Self.retainNearest(
                            (rawIndex, distance),
                            in: &matches,
                            maximumResults: maximumResults
                        )
                    }
                    if evaluated >= maximumEvaluations { break search }
                }
            }
        }
        matches.sort { Self.isPreferred($0, over: $1) }
        return matches
    }

    /// 在已评估候选中保留最多指定数量；满额后仅用更优候选替换末项。
    /// 距离较小者优先，距离相同时按索引稳定排序。
    private static func retainNearest(
        _ candidate: (index: Int32, distance: Int),
        in matches: inout [(index: Int32, distance: Int)],
        maximumResults: Int
    ) {
        if matches.count < maximumResults {
            matches.append(candidate)
            if matches.count == maximumResults {
                matches.sort { isPreferred($0, over: $1) }
            }
            return
        }
        guard let worst = matches.last, isPreferred(candidate, over: worst) else { return }
        matches[matches.count - 1] = candidate
        matches.sort { isPreferred($0, over: $1) }
    }

    /// 比较候选距离，并以索引作为相同距离时的稳定次序。
    private static func isPreferred(
        _ lhs: (index: Int32, distance: Int),
        over rhs: (index: Int32, distance: Int)
    ) -> Bool {
        if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
        // features 已按 identifier 排序，索引顺序就是稳定的次级排序。
        return lhs.index < rhs.index
    }

    /// 循环移动 64 位哈希，从指定偏移截取 16 位分段。
    private static func bandValue(of hash: UInt64, offset: Int) -> UInt16 {
        let rotated = offset == 0
            ? hash
            : (hash >> offset) | (hash << (64 - offset))
        return UInt16(truncatingIfNeeded: rotated)
    }

    /// 将分段编号和 16 位值映射到连续桶数组的位置。
    private static func bucketIndex(band: Int, value: UInt16) -> Int {
        band * (1 << 16) + Int(value)
    }
}

/// 隔离图片特征、感知哈希和缓存状态，串行处理 Vision 观察值的生成与比较。
private actor VisionFeatureEngine {
    /// 同时保存廉价哈希和可选 Vision 特征，使刷新扫描能够分别复用两阶段结果。
    private struct CachedFeature {
        let cacheKey: FeatureCacheKey
        let perceptualHash: UInt64
        var observation: VNFeaturePrintObservation?
    }

    private var features: [String: CachedFeature] = [:]
    private var hasLoadedPersistedHashes = false

    /// 仅保留当前候选资源相关的特征缓存，避免相册变化后长期保留失效条目。
    func retainFeatures(for identifiers: Set<String>) async {
        if !hasLoadedPersistedHashes {
            if let snapshot = await AppStateStore.shared.loadMediaHashCache() {
                let restored = snapshot.compatibleEntries.mapValues {
                    CachedFeature(cacheKey: $0.cacheKey, perceptualHash: $0.hash, observation: nil)
                }
                features.merge(restored) { current, _ in current }
            }
            hasLoadedPersistedHashes = true
        }
        features = features.filter { identifiers.contains($0.key) }
    }

    /// 将当前可持久化的哈希快照交给状态存储，供后续分析复用。
    func persistHashes() async {
        let snapshot = MediaHashCacheSnapshot(
            version: MediaHashCacheSnapshot.currentVersion,
            entries: features.mapValues {
                MediaHashCacheSnapshot.Entry(cacheKey: $0.cacheKey, hash: $0.perceptualHash)
            }
        )
        await AppStateStore.shared.saveMediaHashCache(snapshot)
    }

    /// 仅在资源标识及修改时间、尺寸组成的缓存键匹配时返回哈希。
    func cachedHash(id: String, cacheKey: FeatureCacheKey) -> UInt64? {
        guard let feature = features[id], feature.cacheKey == cacheKey else { return nil }
        return feature.perceptualHash
    }

    /// 批量获取缓存命中的候选哈希，减少逐项跨 actor 访问。
    func cachedHashes(for candidates: [SimilarityCandidate]) -> [String: UInt64] {
        var hashes: [String: UInt64] = [:]
        for candidate in candidates {
            if let hash = cachedHash(id: candidate.id, cacheKey: candidate.cacheKey) {
                hashes[candidate.id] = hash
            }
        }
        return hashes
    }

    /// 保存全相册轻量 dHash；资源版本变化时一并淘汰旧 Vision 特征。
    /// 从缩略图生成并保存感知哈希，供候选筛选和后续扫描使用。
    func storeHash(id: String, cacheKey: FeatureCacheKey, image: CGImage) throws -> UInt64 {
        let hash = try Self.differenceHash(for: image)
        features[id] = CachedFeature(
            cacheKey: cacheKey,
            perceptualHash: hash,
            observation: nil
        )
        return hash
    }

    /// 判断指定资源版本是否已经生成 Vision 特征，避免刷新时重复进行昂贵分析。
    /// 判断是否已有与当前元数据匹配的 Vision 特征观察值。
    func hasObservation(id: String, cacheKey: FeatureCacheKey) -> Bool {
        guard let feature = features[id], feature.cacheKey == cacheKey else { return false }
        return feature.observation != nil
    }

    /// 在后台任务中生成 Vision Feature Print，并在完成后写回 Actor 隔离缓存。
    /// 为缩略图生成并缓存 Vision 特征，供候选对比较使用。
    func storeObservation(
        id: String,
        cacheKey: FeatureCacheKey,
        image: CGImage
    ) async throws {
        let observation = try await Task.detached(priority: .utility) {
            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                throw MediaAnalysisError.unexpected
            }
            return observation
        }.value

        guard var feature = features[id], feature.cacheKey == cacheKey else { return }
        feature.observation = observation
        features[id] = feature
    }

    /// 比较候选对的 Vision 特征，仅返回满足距离阈值的资源对。
    func acceptedPairs(
        from pairs: [CandidatePair],
        maximumDistance: Float
    ) throws -> [AcceptedPair] {
        var accepted: [AcceptedPair] = []
        accepted.reserveCapacity(pairs.count)
        for pair in pairs {
            try Task.checkCancellation()
            guard let first = features[pair.firstID]?.observation,
                  let second = features[pair.secondID]?.observation else {
                continue
            }
            var distance: Float = 0
            try first.computeDistance(&distance, to: second)
            if distance <= maximumDistance {
                accepted.append(AcceptedPair(
                    firstID: pair.firstID,
                    secondID: pair.secondID,
                    distance: distance
                ))
            }
        }
        return accepted
    }

    /// 将缩略图转换为灰度亮度差的 64 位感知哈希，用于低成本候选召回。
    private static func differenceHash(for image: CGImage) throws -> UInt64 {
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let created = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else { throw MediaAnalysisError.unexpected }

        var hash: UInt64 = 0
        var bit: UInt64 = 1
        for row in 0 ..< height {
            for column in 0 ..< (width - 1) {
                if pixels[row * width + column] > pixels[row * width + column + 1] {
                    hash |= bit
                }
                bit <<= 1
            }
        }
        return hash
    }
}

/// 用锁协调 PhotoKit 请求标识与取消状态，处理取消先于请求标识返回的竞态。
private final class ImageRequestController: @unchecked Sendable {
    private let manager: PHImageManager
    private let lock = NSLock()
    nonisolated(unsafe) private var requestID: PHImageRequestID?
    nonisolated(unsafe) private var isCancelled = false

    /// 保存创建请求的 PhotoKit 管理器，以便后续使用同一管理器取消请求。
    init(manager: PHImageManager) { self.manager = manager }

    /// 保存请求标识；若取消先于标识返回，解锁后立即取消该请求。
    nonisolated func store(_ requestID: PHImageRequestID) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { manager.cancelImageRequest(requestID) }
    }

    /// 标记取消并取消已登记的请求；尚未登记时由 `store` 完成取消。
    nonisolated func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        lock.unlock()
        if let requestID { manager.cancelImageRequest(requestID) }
    }
}

/// 用锁保证异步回调只恢复 continuation 一次，避免重复回调造成错误。
private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<Value, Error>?

    /// 保存待恢复的 continuation，后续回调和取消竞争时只能取走一次。
    init(continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }

    /// 首次调用时以结果恢复等待任务；后续回调不再重复恢复。
    nonisolated func resume(returning value: Value) {
        takeContinuation()?.resume(returning: value)
    }

    /// 首次调用时以错误恢复等待任务；后续回调不再重复恢复。
    nonisolated func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    /// 在锁内取走并清空 continuation，防止并发回调重复恢复。
    private nonisolated func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        let result = continuation
        continuation = nil
        lock.unlock()
        return result
    }
}

/// 场景标签仅用于浏览分组，不表示照片可删除。
nonisolated enum PhotoScene: String, Codable, Sendable {
    case city
    case other
}

nonisolated private struct PhotoSceneCacheEntry: Codable, Sendable {
    let key: FeatureCacheKey
    let scene: PhotoScene
}

/// 缓存只保存在本机；变更资源或模型版本会重新分析。
private actor PhotoSceneCache {
    private let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("photo-scenes-v3.json")

    func load() -> [String: PhotoSceneCacheEntry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: PhotoSceneCacheEntry].self, from: data)) ?? [:]
    }

    func save(_ entries: [String: PhotoSceneCacheEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension MediaClassificationService {
    /// 使用系统支持的标签进行保守分类；未下载的资源保持未分类并在以后重试。
    func classifyScenes(
        assets: [PHAsset],
        excludedIDs: Set<String>,
        update: @MainActor ([String]) -> Void
    ) async {
        let supported = await Task.detached(priority: .utility) {
            let request = VNClassifyImageRequest()
            request.revision = VNClassifyImageRequestRevision1
            return Set((try? request.supportedIdentifiers()) ?? [])
        }.value
        guard !Task.isCancelled else { return }
        let cityLabels: Set<String> = ["cityscape", "urban", "street", "skyscraper"]
        let citySupported = cityLabels.intersection(supported)
        guard !citySupported.isEmpty else { return }
        let cache = PhotoSceneCache()
        var entries = await cache.load()
        let images = assets.filter { $0.mediaType == .image && !excludedIDs.contains($0.localIdentifier) }
        let validIDs = Set(images.map(\.localIdentifier))
        entries = entries.filter { validIDs.contains($0.key) }
        var city: [String] = []
        for (index, asset) in images.enumerated() {
            if Task.isCancelled { return }
            let id = asset.localIdentifier
            let key = FeatureCacheKey(modificationDate: asset.modificationDate,
                                      pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
            let scene: PhotoScene
            if let entry = entries[id], entry.key == key {
                scene = entry.scene
            } else {
                guard let image = try? await requestThumbnail(for: asset, targetPixelSize: 256), !Task.isCancelled else { continue }
                let recognized = await Task.detached(priority: .utility) {
                    Self.recognizeScene(image, cityLabels: citySupported)
                }.value
                guard let recognized else { continue }
                scene = recognized
                entries[id] = PhotoSceneCacheEntry(key: key, scene: scene)
            }
            if scene == .city { city.append(id) }
            if index.isMultiple(of: 250) {
                update(city)
                await Task.yield()
            }
            if index > 0 && index.isMultiple(of: 5_000) {
                await cache.save(entries)
            }
        }
        guard !Task.isCancelled else { return }
        update(city)
        await cache.save(entries)
    }

    nonisolated private static func recognizeScene(_ image: CGImage, cityLabels: Set<String>) -> PhotoScene? {
        let request = VNClassifyImageRequest()
        request.revision = VNClassifyImageRequestRevision1
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let confidence = (request.results ?? [])
                .filter { cityLabels.contains($0.identifier) }
                .map(\.confidence).max() ?? 0
            return confidence >= 0.4 ? .city : .other
        } catch {
            return nil
        }
    }
}
