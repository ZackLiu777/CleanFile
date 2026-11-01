//
//  定义图片转换的格式能力、尺寸、背景、元数据与名称冲突策略。
//  请求保存转换选项，检查信息和结果分别描述源图与已提交的输出。
//  批量结果保留逐项成功、失败和取消状态；引擎负责实际验证与文件处理。
//  图片引擎使用请求选择编码和输出策略，页面使用检查结果与批次进度展示状态。
//  类型本身不访问文件；实际格式支持、错误和取消由引擎在执行时判断。
//

import Foundation
import UniformTypeIdentifiers

/// 图片输出格式及其扩展名、类型标识和编码能力。
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

    /// 使用用户熟悉的文件扩展名展示格式，底层编码类型仍保持 JPEG。
    public var displayName: String {
        switch self {
        case .jpeg: "JPG"
        default: rawValue.uppercased()
        }
    }

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

/// 指定不透明填充色或保留透明背景；实际支持情况由引擎验证。
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

/// 控制输出保留全部元数据、移除 GPS 或移除全部元数据。
public enum ImageMetadataPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case preserve
    case removeGPS
    case removeAll

    public var id: Self { self }
}

/// 指定原始尺寸、最长边限制或完整显示图像的方形画布。
public enum ImageResizePolicy: Hashable, Codable, Sendable {
    case original
    case fit(maxPixelDimension: Int)
    /// Exact canvas using the selected background, aspect-fit without cropping; may upscale.
    case square1024
}

/// 目标名称冲突时选择生成唯一名称、覆盖或报错。
public enum ImageNameCollisionPolicy: String, Codable, Sendable {
    case makeUnique
    case overwrite
    case fail
}

/// 不透明背景的 RGB 颜色；分量限制在零到一之间。
public struct ImageFlattenColor: Hashable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// 保存 RGB 分量；非有限数值和越界值会被限制到有效颜色范围。
    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    public static let white = ImageFlattenColor(red: 1, green: 1, blue: 1)
    public static let black = ImageFlattenColor(red: 0, green: 0, blue: 0)

    /// 将非有限分量视为零，其余分量限制在有效颜色范围内。
    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// 图片转换的源、目标和编码选项，包含隐私与文件名冲突策略。
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

    /// 保存源地址、目标目录及编码、元数据、缩放和重名处理选项，不在初始化时执行转换。
    public init(
        sourceURL: URL,
        destinationDirectory: URL,
        outputFormat: ImageOutputFormat,
        quality: Double = 0.9,
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
        if quality.isFinite, (0 ... 1).contains(quality) {
            // Image quality is presented as ten stable presets from 10% to 100%.
            self.quality = max(0.1, (quality * 10).rounded() / 10)
        } else {
            // Preserve invalid input so the engine can report its existing validation error.
            self.quality = quality
        }
        self.metadataPolicy = metadataPolicy
        self.resizePolicy = resizePolicy
        self.flattenColor = flattenColor
        self.background = background
        self.collisionPolicy = collisionPolicy
        self.preferredBaseName = preferredBaseName
    }
}

/// 源图片检查结果，包括类型、尺寸、帧数、文件大小及透明度。
public struct ImageAssetInfo: Hashable, Identifiable, Sendable {
    public var id: URL { sourceURL }

    public let sourceURL: URL
    public let typeIdentifier: String?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let frameCount: Int
    public let fileSizeBytes: Int64
    public let hasAlpha: Bool

    /// 记录源图片类型、尺寸、帧数、文件大小与透明度等检查结果。
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

/// 成功提交的图片输出及其尺寸、大小和处理耗时。
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

    /// 记录源文件、输出文件、格式、大小、像素尺寸和转换耗时。
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

/// 图片检查、解码、编码、路径冲突、提交及取消的可区分错误。
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

/// 将转换错误映射为本地化描述；涉及路径时只展示文件名。
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
            L10n.format("error.unsupported_output", format.displayName)
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

/// 将一次失败与其源文件关联，供批量结果展示。
public struct ImageConversionFailure: Hashable, Identifiable, Sendable {
    public var id: URL { sourceURL }

    public let sourceURL: URL
    public let error: ImageConversionError

    /// 将源文件与转换错误关联，供批量结果逐项报告。
    public init(sourceURL: URL, error: ImageConversionError) {
        self.sourceURL = sourceURL
        self.error = error
    }
}

/// 批量转换的成功项、失败项、请求总数和取消标记。
public struct ImageBatchConversionResult: Hashable, Sendable {
    public let successes: [ImageConversionResult]
    public let failures: [ImageConversionFailure]
    public let totalRequested: Int
    public let wasCancelled: Bool

    /// 保存成功项、失败项、请求总数和取消标志，保留部分成功结果。
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

/// 一次批量转换的完成计数及最近完成的源文件。
public struct ImageBatchProgress: Hashable, Sendable {
    public let completed: Int
    public let total: Int
    public let succeeded: Int
    public let failed: Int
    public let lastSourceURL: URL?

    /// 按完成项数计算进度；空批次返回零。
    public var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    /// 记录批处理完成数、总数、成功与失败数量以及最近完成的源文件。
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

/// 展示层使用的尺寸预设，并映射为引擎接受的尺寸策略。
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
