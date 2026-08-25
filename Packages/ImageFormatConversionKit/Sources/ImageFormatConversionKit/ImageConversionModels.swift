import Foundation
import UniformTypeIdentifiers

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
}

public enum ImageMetadataPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case preserve
    case removeGPS
    case removeAll

    public var id: Self { self }
}

public enum ImageResizePolicy: Hashable, Codable, Sendable {
    case original
    case fit(maxPixelDimension: Int)
}

public enum ImageNameCollisionPolicy: String, Codable, Sendable {
    case makeUnique
    case overwrite
    case fail
}

public struct ImageFlattenColor: Hashable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    public static let white = ImageFlattenColor(red: 1, green: 1, blue: 1)
    public static let black = ImageFlattenColor(red: 0, green: 0, blue: 0)

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

public struct ImageConversionRequest: Hashable, Sendable {
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let outputFormat: ImageOutputFormat
    public let quality: Double
    public let metadataPolicy: ImageMetadataPolicy
    public let resizePolicy: ImageResizePolicy
    public let flattenColor: ImageFlattenColor
    public let collisionPolicy: ImageNameCollisionPolicy
    public let preferredBaseName: String?

    public init(
        sourceURL: URL,
        destinationDirectory: URL,
        outputFormat: ImageOutputFormat,
        quality: Double = 0.85,
        metadataPolicy: ImageMetadataPolicy = .removeGPS,
        resizePolicy: ImageResizePolicy = .original,
        flattenColor: ImageFlattenColor = .white,
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
        self.collisionPolicy = collisionPolicy
        self.preferredBaseName = preferredBaseName
    }
}

public struct ImageAssetInfo: Hashable, Identifiable, Sendable {
    public var id: URL { sourceURL }

    public let sourceURL: URL
    public let typeIdentifier: String?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let frameCount: Int
    public let fileSizeBytes: Int64
    public let hasAlpha: Bool

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

public struct ImageConversionFailure: Hashable, Identifiable, Sendable {
    public var id: URL { sourceURL }

    public let sourceURL: URL
    public let error: ImageConversionError

    public init(sourceURL: URL, error: ImageConversionError) {
        self.sourceURL = sourceURL
        self.error = error
    }
}

public struct ImageBatchConversionResult: Hashable, Sendable {
    public let successes: [ImageConversionResult]
    public let failures: [ImageConversionFailure]
    public let totalRequested: Int
    public let wasCancelled: Bool

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

public enum ImageResizePreset: Int, CaseIterable, Identifiable, Sendable {
    case original = 0
    case ultraHD = 4096
    case large = 2048
    case medium = 1280

    public var id: Self { self }

    public var policy: ImageResizePolicy {
        self == .original ? .original : .fit(maxPixelDimension: rawValue)
    }
}
