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

    private let maximumConcurrentFeatureRequests = 2
    private let sequenceInterval: TimeInterval = 12
    private let maximumPerceptualHashDistance = 16
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
        let featureOutcomes = await generateFeatures(
            for: candidates,
            assetsByIdentifier: assetsByIdentifier,
            progress: progress
        )
        try Task.checkCancellation()

        let availableFeatures = featureOutcomes.compactMap(\.feature)
        let skippedCount = featureOutcomes.count - availableFeatures.count
        let comparisonPairs = candidatePairs(from: availableFeatures)
        progress(MediaAnalysisProgress(
            phase: .comparingImages,
            completed: 0,
            total: comparisonPairs.count
        ))

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
                completed: batchEnd,
                total: comparisonPairs.count
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
            skippedImageCount: skippedCount
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
        let eligibleAssets = assets
            .filter { !$0.mediaSubtypes.contains(.photoScreenshot) }
            .compactMap { asset -> (PHAsset, Date)? in
                guard let creationDate = asset.creationDate else { return nil }
                return (asset, creationDate)
            }
            .sorted { $0.1 < $1.1 }

        var sequences: [[(PHAsset, Date)]] = []
        for item in eligibleAssets {
            if let lastDate = sequences.last?.last?.1,
               item.1.timeIntervalSince(lastDate) <= sequenceInterval {
                sequences[sequences.count - 1].append(item)
            } else {
                sequences.append([item])
            }
        }

        return sequences.filter { $0.count > 1 }.flatMap { sequence in
            let sequenceID = sequence[0].0.localIdentifier
            return sequence.map { asset, creationDate in
                SimilarityCandidate(
                    id: asset.localIdentifier,
                    sequenceID: sequenceID,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    creationDate: creationDate,
                    cacheKey: FeatureCacheKey(
                        modificationDate: asset.modificationDate,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight
                    )
                )
            }
        }
    }

    /// 封装 `generateFeatures` 对应的局部行为，供当前类型在统一入口下复用。
    private func generateFeatures(
        for candidates: [SimilarityCandidate],
        assetsByIdentifier: [String: PHAsset],
        progress: ProgressHandler
    ) async -> [FeatureOutcome] {
        guard !candidates.isEmpty else { return [] }
        var outcomes: [FeatureOutcome] = []
        var nextIndex = 0

        await withTaskGroup(of: FeatureOutcome.self) { group in
            let initialCount = min(maximumConcurrentFeatureRequests, candidates.count)
            for _ in 0 ..< initialCount {
                let candidate = candidates[nextIndex]
                let asset = assetsByIdentifier[candidate.id]
                group.addTask { @MainActor in
                    await generateFeature(for: candidate, asset: asset)
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
                        await generateFeature(for: candidate, asset: asset)
                    }
                    nextIndex += 1
                }
            }
        }
        return outcomes
    }

    /// 封装 `generateFeature` 对应的局部行为，供当前类型在统一入口下复用。
    private func generateFeature(
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
                    sequenceID: candidate.sequenceID,
                    perceptualHash: hash,
                    creationDate: candidate.creationDate
                ))
            }
            let image = try await requestThumbnail(for: asset)
            let hash = try await featureEngine.store(
                id: candidate.id,
                cacheKey: candidate.cacheKey,
                image: image
            )
            return FeatureOutcome(feature: CandidateFeature(
                id: candidate.id,
                sequenceID: candidate.sequenceID,
                perceptualHash: hash,
                creationDate: candidate.creationDate
            ))
        } catch {
            return FeatureOutcome(feature: nil)
        }
    }

    /// 封装 `requestThumbnail` 对应的局部行为，供当前类型在统一入口下复用。
    private func requestThumbnail(for asset: PHAsset) async throws -> CGImage {
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
                    targetSize: CGSize(width: 256, height: 256),
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

    /// 判断 `candidatePairs` 条件是否成立，供调用方选择正确的处理分支。
    private func candidatePairs(from features: [CandidateFeature]) -> [CandidatePair] {
        Dictionary(grouping: features, by: \.sequenceID).values.flatMap { sequence in
            let sorted = sequence.sorted { $0.creationDate < $1.creationDate }
            var pairs: [CandidatePair] = []
            for firstIndex in sorted.indices {
                let upperBound = min(sorted.count, firstIndex + 11)
                guard firstIndex + 1 < upperBound else { continue }
                for secondIndex in (firstIndex + 1) ..< upperBound {
                    let first = sorted[firstIndex]
                    let second = sorted[secondIndex]
                    let hashDistance = (first.perceptualHash ^ second.perceptualHash).nonzeroBitCount
                    if hashDistance <= maximumPerceptualHashDistance {
                        pairs.append(CandidatePair(firstID: first.id, secondID: second.id))
                    }
                }
            }
            return pairs
        }
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
        return lhs.creationDate < rhs.creationDate
    }
}

/// 定义 `SimilarityCandidate` 的值语义数据与相关行为。
private struct SimilarityCandidate: Sendable {
    let id: String
    let sequenceID: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date
    let cacheKey: FeatureCacheKey
}

/// 定义 `FeatureCacheKey` 的值语义数据与相关行为。
private struct FeatureCacheKey: Hashable, Sendable {
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

/// 定义 `CandidateFeature` 的值语义数据与相关行为。
private struct CandidateFeature: Sendable {
    let id: String
    let sequenceID: String
    let perceptualHash: UInt64
    let creationDate: Date
}

/// 定义 `FeatureOutcome` 的值语义数据与相关行为。
private struct FeatureOutcome: Sendable { let feature: CandidateFeature? }
/// 定义 `CandidatePair` 的值语义数据与相关行为。
private struct CandidatePair: Sendable { let firstID: String; let secondID: String }
/// 定义 `AcceptedPair` 的值语义数据与相关行为。
private struct AcceptedPair: Sendable { let firstID: String; let secondID: String; let distance: Float }

/// 使用 Actor 隔离 `VisionFeatureEngine` 的可变状态，确保并发访问安全。
private actor VisionFeatureEngine {
    /// 定义 `CachedFeature` 的值语义数据与相关行为。
    private struct CachedFeature {
        let cacheKey: FeatureCacheKey
        let observation: VNFeaturePrintObservation
        let perceptualHash: UInt64
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

    /// 持久化 `store` 对应的数据，并保持后续恢复所需的信息完整。
    func store(id: String, cacheKey: FeatureCacheKey, image: CGImage) throws -> UInt64 {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw MediaAnalysisError.unexpected
        }
        let hash = try Self.differenceHash(for: image)
        features[id] = CachedFeature(
            cacheKey: cacheKey,
            observation: observation,
            perceptualHash: hash
        )
        return hash
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
