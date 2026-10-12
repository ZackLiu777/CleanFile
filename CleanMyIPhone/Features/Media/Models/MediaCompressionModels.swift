import Foundation
import ImageFormatConversionKit
import Photos

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

nonisolated struct MediaCompressionItem: Identifiable, Sendable {
    let id: String
    let originalBytes: Int64
    let estimatedBytes: Int64
    let isExactOriginal: Bool
    var isLivePhoto = false
}

nonisolated enum MediaCompressionOutcome: Sendable, Equatable {
    case saved(original: Int64, output: Int64, createdAssetID: String? = nil)
    case noReduction(original: Int64)
}

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

nonisolated enum MediaCompressionEstimate {
    private static let imageFormat: ImageOutputFormat = ImageConversionEngine.supportedOutputFormats.contains(.heic) ? .heic : .jpeg
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
