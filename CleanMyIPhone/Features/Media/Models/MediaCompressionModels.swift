//
//  媒体压缩数据模型
//
//  定义压缩分类、单项估算、处理状态与服务返回值。
//  估算值只用于展示，不代表实际输出大小；原图替换是单独的后续操作。
//

import Foundation
import ImageFormatConversionKit
import Photos

/// 压缩入口使用的媒体分类及展示标识；分类与资源筛选规则共同决定候选列表。
nonisolated enum MediaCompressionCategory: String, CaseIterable, Identifiable, Sendable {
    case video, image, live
    var id: Self { self }
    var titleKey: String { switch self {
    case .video: "quick.video"
    case .image: "quick.image"
    case .live: "Live Photos"
    } }
    var symbol: String { switch self {
    case .video: "video"
    case .image: "photo"
    case .live: "livephoto"
    } }

    @MainActor
    /// 从当前资源快照筛选此分类的候选，图片分类也包含相关相似图、截图和 Live Photo。
    func assets(in library: PhotoLibraryViewModel) -> [PHAsset] {
        let result: MediaClassificationResult?
        switch library.analysisState {
        case .success(let value), .partialFailure(let value): result = value
        default: result = nil
        }
        let photoIDs = Set(result?.similarImageIDs ?? []).union(result?.screenshotIDs ?? [])
        return library.assets.filter { asset in
            switch self {
            case .video: asset.mediaType == .video
            case .live: asset.mediaSubtypes.contains(.photoLive)
            case .image:
                asset.mediaType == .image
                    && (asset.mediaSubtypes.contains(.photoLive) || photoIDs.contains(asset.localIdentifier)
                        || asset.mediaSubtypes.contains(.photoScreenshot))
            }
        }
    }
}

/// 一个候选资源的原始大小、输出估算和大小是否精确等展示数据。
nonisolated struct MediaCompressionItem: Identifiable, Sendable {
    let id: String
    let originalBytes: Int64
    let estimatedBytes: Int64
    let isExactOriginal: Bool
    var isLivePhoto = false
}

/// 压缩服务的结果：已保存更小副本，或输出没有减少而保留原件。
nonisolated enum MediaCompressionOutcome: Sendable, Equatable {
    case saved(original: Int64, output: Int64, createdAssetID: String? = nil)
    case noReduction(original: Int64)
}

/// 单项压缩与替换过程的展示状态，包含失败和取消。
nonisolated enum MediaCompressionItemState: Equatable, Sendable {
    case processing
    case saved(original: Int64, output: Int64)
    case replaced(original: Int64, output: Int64)
    case noReduction(original: Int64)
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self { case .replaced, .noReduction: true; default: false }
    }
}

/// 根据媒体类型和图片转换估算生成展示大小，不执行实际转换。
nonisolated enum MediaCompressionEstimate {
    private static let imageFormat: ImageOutputFormat = ImageConversionEngine.supportedOutputFormats.contains(.heic) ? .heic : .jpeg
    /// 对视频和 Live Photo 使用比例估算，普通图片使用转换引擎估算；无有效原大小时返回零。
    static func bytes(original: Int64, width: Int, height: Int, type: String?, category: MediaCompressionCategory) -> Int64 {
        guard original > 0 else { return 0 }
        if category == .video { return Int64(Double(original) * 0.55) }
        // Live Photo totals contain a still plus motion; both components are retained.
        if category == .live { return Int64(Double(original) * 0.65) }
        let info = ImageAssetInfo(sourceURL: URL(fileURLWithPath: "/estimate"), typeIdentifier: type,
                                  pixelWidth: width, pixelHeight: height, frameCount: 1,
                                  fileSizeBytes: original, hasAlpha: false)
        return ConversionSizeEstimate.image(infos: [info], format: imageFormat, quality: 0.5,
                                            resize: .original, metadata: .preserve)?.likelyBytes ?? original
    }
}
