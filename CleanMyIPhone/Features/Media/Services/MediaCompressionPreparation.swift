//
//  压缩清单准备
//
//  筛选资源、先发布有限预览，再根据精确大小样本校准估算并构建索引。
//  精确值优先于校准或回退估算；整个准备过程支持取消且不修改相册。
//

import Foundation
import Photos

/// Immutable metadata and indexes are prepared once, off the UI executor.
/// 不可变压缩清单：Live Photo 排在前面，同时提供按标识查询的索引和字节汇总。
nonisolated struct MediaCompressionCatalog: Sendable {
    let items: [MediaCompressionItem]
    private let liveCount: Int
    var liveItems: ArraySlice<MediaCompressionItem> { items.prefix(liveCount) }
    var photoItems: ArraySlice<MediaCompressionItem> { items.dropFirst(liveCount) }
    let byID: [String: Int]
    let originalBytes: Int64
    let outputBytes: Int64

    /// 建立排序后的索引与汇总；展示估算限制在零和原始大小之间。
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

/// 在后台准备压缩候选、预览及大小校准数据，不对相册资源执行写操作。
actor MediaCompressionPreparation {
    /// 先发布最多 60 项预览，再按资源类型汇总至少三个精确大小样本的中位数，构造完整清单。
    /// 循环和预览回调之后检查取消，避免继续处理已失效的请求。
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

    /// 按当前分类筛选视频、Live Photo 或符合快速清理条件的图片。
    private func includes(_ asset: PHAsset, category: MediaCompressionCategory, photoIDs: Set<String>) -> Bool {
        switch category {
        case .video: asset.mediaType == .video
        case .live: asset.mediaSubtypes.contains(.photoLive)
        case .image: asset.mediaType == .image && (asset.mediaSubtypes.contains(.photoLive)
            || asset.mediaSubtypes.contains(.photoScreenshot) || photoIDs.contains(asset.localIdentifier))
        }
    }

    /// 优先使用精确大小，其次使用同类校准系数，最后使用回退估算生成展示项。
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
