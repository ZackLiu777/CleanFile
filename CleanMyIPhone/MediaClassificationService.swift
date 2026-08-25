import CoreGraphics
import Foundation
import Photos
import UIKit
import Vision

@MainActor
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
        await featureEngine.reset()

        progress(MediaAnalysisProgress(
            phase: .generatingFeatures,
            completed: 0,
            total: candidates.count
        ))
        let featureOutcomes = await generateFeatures(for: candidates, progress: progress)
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
        for (index, pair) in comparisonPairs.enumerated() {
            try Task.checkCancellation()
            if let distance = try? await featureEngine.distance(
                between: pair.firstID,
                and: pair.secondID
            ), distance <= maximumFeaturePrintDistance {
                acceptedPairs.append(AcceptedPair(
                    firstID: pair.firstID,
                    secondID: pair.secondID,
                    distance: distance
                ))
            }
            progress(MediaAnalysisProgress(
                phase: .comparingImages,
                completed: index + 1,
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
                    creationDate: creationDate
                )
            }
        }
    }

    private func generateFeatures(
        for candidates: [SimilarityCandidate],
        progress: ProgressHandler
    ) async -> [FeatureOutcome] {
        guard !candidates.isEmpty else { return [] }
        var outcomes: [FeatureOutcome] = []
        var nextIndex = 0

        await withTaskGroup(of: FeatureOutcome.self) { group in
            let initialCount = min(maximumConcurrentFeatureRequests, candidates.count)
            for _ in 0 ..< initialCount {
                let candidate = candidates[nextIndex]
                group.addTask { @MainActor in await generateFeature(for: candidate) }
                nextIndex += 1
            }

            while let outcome = await group.next() {
                outcomes.append(outcome)
                progress(MediaAnalysisProgress(
                    phase: .generatingFeatures,
                    completed: outcomes.count,
                    total: candidates.count
                ))
                if Task.isCancelled {
                    group.cancelAll()
                } else if nextIndex < candidates.count {
                    let candidate = candidates[nextIndex]
                    group.addTask { @MainActor in await generateFeature(for: candidate) }
                    nextIndex += 1
                }
            }
        }
        return outcomes
    }

    private func generateFeature(for candidate: SimilarityCandidate) async -> FeatureOutcome {
        guard !Task.isCancelled,
              let asset = PHAsset.fetchAssets(
                withLocalIdentifiers: [candidate.id],
                options: nil
              ).firstObject else {
            return FeatureOutcome(feature: nil)
        }

        do {
            let image = try await requestThumbnail(for: asset)
            let hash = try await featureEngine.store(id: candidate.id, image: image)
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

    private func requestThumbnail(for asset: PHAsset) async throws -> CGImage {
        let controller = ImageRequestController(manager: imageManager)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = ContinuationGate<CGImage>(continuation: continuation)
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.isNetworkAccessAllowed = false

                let requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: 384, height: 384),
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
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

private struct SimilarityCandidate: Sendable {
    let id: String
    let sequenceID: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date
}

private struct CandidateFeature: Sendable {
    let id: String
    let sequenceID: String
    let perceptualHash: UInt64
    let creationDate: Date
}

private struct FeatureOutcome: Sendable { let feature: CandidateFeature? }
private struct CandidatePair: Sendable { let firstID: String; let secondID: String }
private struct AcceptedPair: Sendable { let firstID: String; let secondID: String; let distance: Float }

private actor VisionFeatureEngine {
    private var observations: [String: VNFeaturePrintObservation] = [:]

    func reset() {
        observations.removeAll(keepingCapacity: true)
    }

    func store(id: String, image: CGImage) throws -> UInt64 {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw MediaAnalysisError.unexpected
        }
        observations[id] = observation
        return try Self.differenceHash(for: image)
    }

    func distance(between firstID: String, and secondID: String) throws -> Float {
        guard let first = observations[firstID], let second = observations[secondID] else {
            throw MediaAnalysisError.unexpected
        }
        var distance: Float = 0
        try first.computeDistance(&distance, to: second)
        return distance
    }

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

private final class ImageRequestController: @unchecked Sendable {
    private let manager: PHImageManager
    private let lock = NSLock()
    nonisolated(unsafe) private var requestID: PHImageRequestID?
    nonisolated(unsafe) private var isCancelled = false

    init(manager: PHImageManager) { self.manager = manager }

    nonisolated func store(_ requestID: PHImageRequestID) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { manager.cancelImageRequest(requestID) }
    }

    nonisolated func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        lock.unlock()
        if let requestID { manager.cancelImageRequest(requestID) }
    }
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<Value, Error>?

    init(continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }

    nonisolated func resume(returning value: Value) {
        takeContinuation()?.resume(returning: value)
    }

    nonisolated func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private nonisolated func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        let result = continuation
        continuation = nil
        lock.unlock()
        return result
    }
}
