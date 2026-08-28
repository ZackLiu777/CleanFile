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
/// 定义 `MediaClassificationService` 的值语义数据与相关行为。
struct MediaClassificationService {
    typealias ProgressHandler = @MainActor @Sendable (MediaAnalysisProgress) -> Void

    /// 轻量哈希只处理 64×64 缩略图，可以用略高的有界并发缩短相册读取时间。
    private let maximumConcurrentHashRequests = 4
    /// Vision 特征生成仍属于 CPU 密集任务，限制为两路以避免扫描时挤占 UI 和内存。
    private let maximumConcurrentVisionRequests = 2
    private let maximumPerceptualHashDistance = 16
    private let maximumHashMatchesPerImage = 32
    // Vision has no universal distance threshold. Start conservatively and
    // calibrate this value against representative user photo libraries.
    private let maximumFeaturePrintDistance: Float = 0.55
    private let imageManager = PHCachingImageManager()
    private let featureEngine = VisionFeatureEngine()

    /// 执行 `analyze` 分析流程，在遵守文件访问边界的前提下生成结果。
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

        let availableHashes = hashOutcomes.compactMap(\.feature)
        let hashSkippedCount = hashOutcomes.count - availableHashes.count
        let comparisonPairs = candidatePairs(from: availableHashes)
        let comparisonIdentifiers = Set(comparisonPairs.flatMap { [$0.firstID, $0.secondID] })
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
            if let matches = try? await featureEngine.acceptedPairs(
                from: Array(comparisonPairs[batchStart ..< batchEnd]),
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

    /// 封装 `categories` 对应的局部行为，供当前类型在统一入口下复用。
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

    /// 解析 `classifyVideo` 对应的业务语义，并返回稳定的分类或映射结果。
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

    /// 封装 `similarityCandidates` 对应的局部行为，供当前类型在统一入口下复用。
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
        var nextIndex = 0

        await withTaskGroup(of: FeatureOutcome.self) { group in
            let initialCount = min(maximumConcurrentHashRequests, candidates.count)
            for _ in 0 ..< initialCount {
                let candidate = candidates[nextIndex]
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
                } else if nextIndex < candidates.count {
                    let candidate = candidates[nextIndex]
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

    /// 判断 `shouldReportProgress` 条件是否成立，供调用方选择正确的处理分支。
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

    /// 判断 `candidatePairs` 条件是否成立，供调用方选择正确的处理分支。
    private func candidatePairs(from features: [CandidateFeature]) -> [CandidatePair] {
        let index = HammingBKTree()
        var pairs: [CandidatePair] = []

        for feature in features.sorted(by: { $0.id < $1.id }) {
            let matches = index.matches(
                hash: feature.perceptualHash,
                maximumDistance: maximumPerceptualHashDistance,
                maximumResults: maximumHashMatchesPerImage
            )

            pairs.append(contentsOf: matches.map { match in
                CandidatePair(firstID: match.id, secondID: feature.id)
            })
            index.insert(feature)
        }

        return pairs
    }

    /// 创建 `makeConservativeGroups` 所需的值或资源，统一封装构造细节。
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

    /// 封装 `preferredKeeperOrder` 对应的局部行为，供当前类型在统一入口下复用。
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

/// 定义 `SimilarityCandidate` 的值语义数据与相关行为。
private struct SimilarityCandidate: Sendable {
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let cacheKey: FeatureCacheKey
}

/// 定义 `FeatureCacheKey` 的值语义数据与相关行为。
nonisolated private struct FeatureCacheKey: Hashable, Sendable {
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

/// 定义 `CandidateFeature` 的值语义数据与相关行为。
private struct CandidateFeature: Sendable {
    let id: String
    let perceptualHash: UInt64
}

/// 定义 `FeatureOutcome` 的值语义数据与相关行为。
private struct FeatureOutcome: Sendable { let feature: CandidateFeature? }
/// 定义 `CandidatePair` 的值语义数据与相关行为。
private struct CandidatePair: Sendable { let firstID: String; let secondID: String }
/// 定义 `AcceptedPair` 的值语义数据与相关行为。
private struct AcceptedPair: Sendable { let firstID: String; let secondID: String; let distance: Float }

/// 使用 BK-tree 按汉明距离索引全相册感知哈希，避免产生全量平方级图片对。
private final class HammingBKTree {
    /// 保存同一哈希的图片以及按汉明距离分叉的子节点。
    private final class Node {
        let hash: UInt64
        var features: [CandidateFeature]
        var children: [Int: Node] = [:]

        /// 创建一个以首张图片为代表值的哈希节点。
        init(feature: CandidateFeature) {
            hash = feature.perceptualHash
            features = [feature]
        }
    }

    private var root: Node?

    /// 将图片特征插入对应汉明距离分支；相同哈希保存在同一节点。
    func insert(_ feature: CandidateFeature) {
        guard let root else {
            self.root = Node(feature: feature)
            return
        }

        var node = root
        while true {
            let distance = Self.distance(node.hash, feature.perceptualHash)
            if distance == 0 {
                node.features.append(feature)
                return
            }
            if let child = node.children[distance] {
                node = child
            } else {
                node.children[distance] = Node(feature: feature)
                return
            }
        }
    }

    /// 在查询阶段直接保留有限个最近邻，避免密集相似哈希先形成平方级临时候选数组。
    func matches(
        hash: UInt64,
        maximumDistance: Int,
        maximumResults: Int
    ) -> [CandidateFeature] {
        guard let root, maximumResults > 0 else { return [] }
        var matches: [(feature: CandidateFeature, distance: Int)] = []
        var pending = [root]

        while let node = pending.popLast() {
            let distance = Self.distance(node.hash, hash)
            if distance <= maximumDistance {
                // 同一节点中的图片拥有完全相同的哈希。最多取结果上限数量，
                // 即使图库存在数千张相同截图，也不会逐次复制整个节点数组。
                let nodeMatches = node.features.prefix(maximumResults).map {
                    (feature: $0, distance: distance)
                }
                matches.append(contentsOf: nodeMatches)
                matches.sort {
                    if $0.distance != $1.distance { return $0.distance < $1.distance }
                    return $0.feature.id < $1.feature.id
                }
                if matches.count > maximumResults {
                    matches.removeLast(matches.count - maximumResults)
                }
            }

            // 结果已满时可将搜索半径收紧到当前最差候选距离，减少无效分支。
            let searchRadius = matches.count == maximumResults
                ? min(maximumDistance, matches.last?.distance ?? maximumDistance)
                : maximumDistance
            let lowerBound = max(0, distance - searchRadius)
            let upperBound = distance + searchRadius
            pending.append(contentsOf: node.children.compactMap { edge, child in
                (lowerBound ... upperBound).contains(edge) ? child : nil
            })
        }

        return matches.map(\.feature)
    }

    /// 计算两个 64 位感知哈希之间不同位的数量。
    private static func distance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}

/// 使用 Actor 隔离 `VisionFeatureEngine` 的可变状态，确保并发访问安全。
private actor VisionFeatureEngine {
    /// 同时保存廉价哈希和可选 Vision 特征，使刷新扫描能够分别复用两阶段结果。
    private struct CachedFeature {
        let cacheKey: FeatureCacheKey
        let perceptualHash: UInt64
        var observation: VNFeaturePrintObservation?
    }

    private var features: [String: CachedFeature] = [:]

    /// 封装 `retainFeatures` 对应的局部行为，供当前类型在统一入口下复用。
    func retainFeatures(for identifiers: Set<String>) {
        features = features.filter { identifiers.contains($0.key) }
    }

    /// 封装 `cachedHash` 对应的局部行为，供当前类型在统一入口下复用。
    func cachedHash(id: String, cacheKey: FeatureCacheKey) -> UInt64? {
        guard let feature = features[id], feature.cacheKey == cacheKey else { return nil }
        return feature.perceptualHash
    }

    /// 保存全相册轻量 dHash；资源版本变化时一并淘汰旧 Vision 特征。
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
    func hasObservation(id: String, cacheKey: FeatureCacheKey) -> Bool {
        guard let feature = features[id], feature.cacheKey == cacheKey else { return false }
        return feature.observation != nil
    }

    /// 在后台任务中生成 Vision Feature Print，并在完成后写回 Actor 隔离缓存。
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

    /// 封装 `acceptedPairs` 对应的局部行为，供当前类型在统一入口下复用。
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

    /// 封装 `differenceHash` 对应的局部行为，供当前类型在统一入口下复用。
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

/// 封装 `ImageRequestController` 的引用语义、状态与业务行为。
private final class ImageRequestController: @unchecked Sendable {
    private let manager: PHImageManager
    private let lock = NSLock()
    nonisolated(unsafe) private var requestID: PHImageRequestID?
    nonisolated(unsafe) private var isCancelled = false

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(manager: PHImageManager) { self.manager = manager }

    /// 持久化 `store` 对应的数据，并保持后续恢复所需的信息完整。
    nonisolated func store(_ requestID: PHImageRequestID) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { manager.cancelImageRequest(requestID) }
    }

    /// 取消 `cancel` 对应的进行中任务，并收敛到可继续操作的状态。
    nonisolated func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        lock.unlock()
        if let requestID { manager.cancelImageRequest(requestID) }
    }
}

/// 封装 `ContinuationGate` 的引用语义、状态与业务行为。
private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<Value, Error>?

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }

    /// 启动 `resume` 对应流程，并初始化本轮任务需要的状态。
    nonisolated func resume(returning value: Value) {
        takeContinuation()?.resume(returning: value)
    }

    /// 启动 `resume` 对应流程，并初始化本轮任务需要的状态。
    nonisolated func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    /// 封装 `takeContinuation` 对应的局部行为，供当前类型在统一入口下复用。
    private nonisolated func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        let result = continuation
        continuation = nil
        lock.unlock()
        return result
    }
}
