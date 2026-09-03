//
//  文件职责：定义 ImageConversion 领域使用的数据模型与状态语义。
//  所属模块：ImageFormatConversionKit。
//

import Foundation
import UniformTypeIdentifiers

/// 定义 `ImageOutputFormat` 使用的有限状态或选项集合。
public enum ImageOutputFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case jpeg
    case png
    case heic
    case heif
    case tiff
    case webp
    case gif
    case bmp

    public var id: Self { self }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .heif: "heif"
        case .tiff: "tiff"
        case .webp: "webp"
        case .gif: "gif"
        case .bmp: "bmp"
        }
    }

    public var typeIdentifier: String {
        switch self {
        case .jpeg: UTType.jpeg.identifier
        case .png: UTType.png.identifier
        case .heic: UTType.heic.identifier
        case .heif: UTType.heif.identifier
        case .tiff: UTType.tiff.identifier
        case .webp: UTType.webP.identifier
        case .gif: UTType.gif.identifier
        case .bmp: UTType.bmp.identifier
        }
    }

    public var supportsQuality: Bool {
        self == .jpeg || self == .heic || self == .heif || self == .webp
    }

    public var requiresOpaquePixels: Bool {
        self == .jpeg || self == .bmp
    }

    /// Only expose full alpha export for codecs validated by this pipeline.
    public var supportsTransparentBackground: Bool {
        self == .png || self == .tiff
    }
}

public enum ImageBackground: String, CaseIterable, Identifiable, Sendable {
    case white, black, transparent
    public var id: Self { self }
    public var color: ImageFlattenColor? {
        switch self {
        case .white: .white
        case .black: .black
        case .transparent: nil
        }
    }
}

/// 定义 `ImageMetadataPolicy` 使用的有限状态或选项集合。
public enum ImageMetadataPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case preserve
    case removeGPS
    case removeAll

    public var id: Self { self }
}

/// 定义 `ImageResizePolicy` 使用的有限状态或选项集合。
public enum ImageResizePolicy: Hashable, Codable, Sendable {
    case original
    case fit(maxPixelDimension: Int)
    /// Exact canvas using the selected background, aspect-fit without cropping; may upscale.
    case square1024
}

/// 定义 `ImageNameCollisionPolicy` 使用的有限状态或选项集合。
public enum ImageNameCollisionPolicy: String, Codable, Sendable {
    case makeUnique
    case overwrite
    case fail
}

/// 定义 `ImageFlattenColor` 的值语义数据与相关行为。
public struct ImageFlattenColor: Hashable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    public static let white = ImageFlattenColor(red: 1, green: 1, blue: 1)
    public static let black = ImageFlattenColor(red: 0, green: 0, blue: 0)

    /// 封装 `clamped` 对应的局部行为，供当前类型在统一入口下复用。
    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// 定义 `ImageConversionRequest` 的值语义数据与相关行为。
public struct ImageConversionRequest: Hashable, Sendable {
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let outputFormat: ImageOutputFormat
    public let quality: Double
    public let metadataPolicy: ImageMetadataPolicy
    public let resizePolicy: ImageResizePolicy
    public let flattenColor: ImageFlattenColor
    public let background: ImageBackground?
    public let collisionPolicy: ImageNameCollisionPolicy
    public let preferredBaseName: String?

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        sourceURL: URL,
        destinationDirectory: URL,
        outputFormat: ImageOutputFormat,
        quality: Double = 0.85,
        metadataPolicy: ImageMetadataPolicy = .removeGPS,
        resizePolicy: ImageResizePolicy = .original,
        flattenColor: ImageFlattenColor = .white,
        background: ImageBackground? = nil,
        collisionPolicy: ImageNameCollisionPolicy = .makeUnique,
        preferredBaseName: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.destinationDirectory = destinationDirectory
        self.outputFormat = outputFormat
        self.quality = quality
        self.metadataPolicy = metadataPolicy
        self.resizePolicy = resizePolicy
        self.flattenColor = flattenColor
        self.background = background
        self.collisionPolicy = collisionPolicy
        self.preferredBaseName = preferredBaseName
    }
}

/// 定义 `ImageAssetInfo` 的值语义数据与相关行为。
public struct ImageAssetInfo: Hashable, Identifiable, Sendable {
    public var id: URL { sourceURL }

    public let sourceURL: URL
    public let typeIdentifier: String?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let frameCount: Int
    public let fileSizeBytes: Int64
    public let hasAlpha: Bool

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        sourceURL: URL,
        typeIdentifier: String?,
        pixelWidth: Int,
        pixelHeight: Int,
        frameCount: Int,
        fileSizeBytes: Int64,
        hasAlpha: Bool
    ) {
        self.sourceURL = sourceURL
        self.typeIdentifier = typeIdentifier
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.frameCount = frameCount
        self.fileSizeBytes = fileSizeBytes
        self.hasAlpha = hasAlpha
    }
}

/// 定义 `ImageConversionResult` 的值语义数据与相关行为。
public struct ImageConversionResult: Hashable, Identifiable, Sendable {
    public var id: URL { outputURL }

    public let sourceURL: URL
    public let outputURL: URL
    public let outputFormat: ImageOutputFormat
    public let sourceBytes: Int64
    public let outputBytes: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let duration: Duration

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        sourceURL: URL,
        outputURL: URL,
        outputFormat: ImageOutputFormat,
        sourceBytes: Int64,
        outputBytes: Int64,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: Duration
    ) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.outputFormat = outputFormat
        self.sourceBytes = sourceBytes
        self.outputBytes = outputBytes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
    }
}

/// 定义 `ImageConversionError` 使用的有限状态或选项集合。
public enum ImageConversionError: Error, Hashable, Sendable {
    case sourceNotReachable(URL)
    case cannotOpenSource(URL)
    case unsupportedInputFormat(URL)
    case invalidImageProperties(URL)
    case animatedImageUnsupported(frameCount: Int)
    case unsupportedOutputFormat(ImageOutputFormat)
    case invalidQuality(Double)
    case invalidMaximumPixelDimension(Int)
    case cannotDecode(URL)
    case cannotFlattenTransparency
    case cannotCreateDestination(URL)
    case cannotFinalizeDestination(URL)
    case destinationExists(URL)
    case destinationBusy(URL)
    case cannotReserveOutputName(URL)
    case fileCommitFailed(String)
    case cancelled
    case unexpected(String)
}

/// 扩展 `ImageConversionError`，集中实现当前文件所需的附加能力。
extension ImageConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .sourceNotReachable(url):
            L10n.format("error.source_not_reachable", url.lastPathComponent)
        case let .cannotOpenSource(url):
            L10n.format("error.cannot_open_source", url.lastPathComponent)
        case let .unsupportedInputFormat(url):
            L10n.format("error.unsupported_input", url.lastPathComponent)
        case let .invalidImageProperties(url):
            L10n.format("error.invalid_properties", url.lastPathComponent)
        case let .animatedImageUnsupported(frameCount):
            L10n.format("error.animated_unsupported", frameCount)
        case let .unsupportedOutputFormat(format):
            L10n.format("error.unsupported_output", format.rawValue.uppercased())
        case let .invalidQuality(quality):
            L10n.format("error.invalid_quality", quality)
        case let .invalidMaximumPixelDimension(value):
            L10n.format("error.invalid_dimension", value)
        case let .cannotDecode(url):
            L10n.format("error.cannot_decode", url.lastPathComponent)
        case .cannotFlattenTransparency:
            L10n.string("error.cannot_flatten")
        case let .cannotCreateDestination(url):
            L10n.format("error.cannot_create_destination", url.lastPathComponent)
        case let .cannotFinalizeDestination(url):
            L10n.format("error.cannot_finalize", url.lastPathComponent)
        case let .destinationExists(url):
            L10n.format("error.destination_exists", url.lastPathComponent)
        case let .destinationBusy(url):
            L10n.format("error.destination_busy", url.lastPathComponent)
        case let .cannotReserveOutputName(url):
            L10n.format("error.cannot_reserve", url.lastPathComponent)
        case let .fileCommitFailed(reason):
            L10n.format("error.commit_failed", reason)
        case .cancelled:
            L10n.string("error.cancelled")
        case let .unexpected(message):
            L10n.format("error.unexpected", message)
        }
    }
}

/// 定义 `ImageConversionFailure` 的值语义数据与相关行为。
public struct ImageConversionFailure: Hashable, Identifiable, Sendable {
    public var id: URL { sourceURL }

    public let sourceURL: URL
    public let error: ImageConversionError

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(sourceURL: URL, error: ImageConversionError) {
        self.sourceURL = sourceURL
        self.error = error
    }
}

/// 定义 `ImageBatchConversionResult` 的值语义数据与相关行为。
public struct ImageBatchConversionResult: Hashable, Sendable {
    public let successes: [ImageConversionResult]
    public let failures: [ImageConversionFailure]
    public let totalRequested: Int
    public let wasCancelled: Bool

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        successes: [ImageConversionResult],
        failures: [ImageConversionFailure],
        totalRequested: Int,
        wasCancelled: Bool
    ) {
        self.successes = successes
        self.failures = failures
        self.totalRequested = totalRequested
        self.wasCancelled = wasCancelled
    }
}

/// 定义 `ImageBatchProgress` 的值语义数据与相关行为。
public struct ImageBatchProgress: Hashable, Sendable {
    public let completed: Int
    public let total: Int
    public let succeeded: Int
    public let failed: Int
    public let lastSourceURL: URL?

    public var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        completed: Int,
        total: Int,
        succeeded: Int,
        failed: Int,
        lastSourceURL: URL?
    ) {
        self.completed = completed
        self.total = total
        self.succeeded = succeeded
        self.failed = failed
        self.lastSourceURL = lastSourceURL
    }
}

/// 定义 `ImageResizePreset` 使用的有限状态或选项集合。
public enum ImageResizePreset: Int, CaseIterable, Identifiable, Sendable {
    case original = 0
    case ultraHD = 4096
    case large = 2048
    case medium = 1280
    case square1024 = 1024

    public var id: Self { self }

    public var policy: ImageResizePolicy {
        switch self {
        case .original: .original
        case .square1024: .square1024
        default: .fit(maxPixelDimension: rawValue)
        }
    }
}
