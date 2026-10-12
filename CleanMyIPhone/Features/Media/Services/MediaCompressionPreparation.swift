import Foundation
import Photos

/// Immutable metadata and indexes are prepared once, off the UI executor.
nonisolated struct MediaCompressionCatalog: Sendable {
    let items: [MediaCompressionItem]
    private let liveCount: Int
    var liveItems: ArraySlice<MediaCompressionItem> { items.prefix(liveCount) }
    var photoItems: ArraySlice<MediaCompressionItem> { items.dropFirst(liveCount) }
    let byID: [String: Int]
    let originalBytes: Int64
    let outputBytes: Int64

    init(items: [MediaCompressionItem]) {
        let live = items.filter(\.isLivePhoto)
        liveCount = live.count
        self.items = live + items.filter { !$0.isLivePhoto }
        var index: [String: Int] = [:]
        index.reserveCapacity(items.count)
        var original: Int64 = 0
        var output: Int64 = 0
        for (offset, item) in self.items.enumerated() {
            index[item.id] = offset
            original += max(0, item.originalBytes)
            output += min(max(0, item.originalBytes), max(0, item.estimatedBytes))
        }
        byID = index
        originalBytes = original
        outputBytes = output
    }
}

actor MediaCompressionPreparation {
    func prepare(
        category: MediaCompressionCategory,
        assets: [PHAsset],
        exactSizes: [String: Int64],
        classification: MediaClassificationResult?,
        preview: @Sendable ([MediaCompressionItem]) async -> Void
    ) async throws -> MediaCompressionCatalog {
        let interval = MediaPerformance.begin("Compression Prepare")
        defer { MediaPerformance.end("Compression Prepare", id: interval) }
        try Task.checkCancellation()
        let photoIDs = Set(classification?.similarImageIDs ?? []).union(classification?.screenshotIDs ?? [])
        var firstItems: [MediaCompressionItem] = []
        // Publish a bounded first screen before calibrating or estimating the whole library.
        for asset in assets {
            try Task.checkCancellation()
            guard includes(asset, category: category, photoIDs: photoIDs) else { continue }
            firstItems.append(item(asset, category: category, exactSizes: exactSizes, calibration: [:]))
            if firstItems.count == 60 { break }
        }
        await preview(firstItems)
        try Task.checkCancellation()

        var samples: [String: [Double]] = [:]
        for asset in assets {
            try Task.checkCancellation()
            guard let bytes = exactSizes[asset.localIdentifier] else { continue }
            let denominator = PhotoLibraryViewModel.calibrationDenominator(for: asset)
            guard denominator > 0 else { continue }
            samples[PhotoLibraryViewModel.calibrationKey(for: asset), default: []].append(Double(bytes) / denominator)
        }
        let calibration = samples.compactMapValues { values -> Double? in
            guard values.count >= 3 else { return nil }
            let sorted = values.sorted(), middle = values.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }
        var items: [MediaCompressionItem] = []
        for asset in assets {
            try Task.checkCancellation()
            guard includes(asset, category: category, photoIDs: photoIDs) else { continue }
            items.append(item(asset, category: category, exactSizes: exactSizes, calibration: calibration))
        }
        try Task.checkCancellation()
        return MediaCompressionCatalog(items: items)
    }

    private func includes(_ asset: PHAsset, category: MediaCompressionCategory, photoIDs: Set<String>) -> Bool {
        switch category {
        case .video: asset.mediaType == .video
        case .live: asset.mediaSubtypes.contains(.photoLive)
        case .image: asset.mediaType == .image && (asset.mediaSubtypes.contains(.photoLive)
            || asset.mediaSubtypes.contains(.photoScreenshot) || photoIDs.contains(asset.localIdentifier))
        }
    }

    private func item(_ asset: PHAsset, category: MediaCompressionCategory,
                      exactSizes: [String: Int64], calibration: [String: Double]) -> MediaCompressionItem {
        let original: Int64
        if let exact = exactSizes[asset.localIdentifier] { original = exact }
        else if let coefficient = calibration[PhotoLibraryViewModel.calibrationKey(for: asset)] {
            original = Int64((PhotoLibraryViewModel.calibrationDenominator(for: asset) * coefficient).rounded())
        } else { original = PhotoLibraryViewModel.fallbackEstimatedByteCount(for: asset) }
        let live = asset.mediaSubtypes.contains(.photoLive)
        return MediaCompressionItem(id: asset.localIdentifier, originalBytes: original,
            estimatedBytes: MediaCompressionEstimate.bytes(original: original, width: asset.pixelWidth,
                height: asset.pixelHeight, type: PhotoLibraryViewModel.contentTypeIdentifier(for: asset), category: live ? .live : category),
            isExactOriginal: exactSizes[asset.localIdentifier] != nil, isLivePhoto: live)
    }
}
