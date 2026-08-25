import Foundation
import UniformTypeIdentifiers

public enum VideoOutputContainer: String, CaseIterable, Identifiable, Sendable {
    case mp4
    case mov
    case m4v

    public var id: Self { self }
    public var fileExtension: String { rawValue }
}

public enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264
    case hevc
    case proRes422
    case proRes4444

    public var id: Self { self }
}

public enum VideoResolutionPreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case ultraHD
    case fullHD
    case hd
    case sd

    public var id: Self { self }
}

public enum VideoConversionStatus: Hashable, Sendable {
    case ready
    case converting
    case completed(URL)
    case failed(String)
    case cancelled
}

public struct VideoConversionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let sourceBytes: Int64
    public var status: VideoConversionStatus

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceBytes: Int64,
        status: VideoConversionStatus = .ready
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceBytes = sourceBytes
        self.status = status
    }
}

public struct VideoConversionRequest: Sendable {
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let container: VideoOutputContainer
    public let codec: VideoCodec
    public let resolution: VideoResolutionPreset

    public init(
        sourceURL: URL,
        destinationDirectory: URL,
        container: VideoOutputContainer,
        codec: VideoCodec,
        resolution: VideoResolutionPreset
    ) {
        self.sourceURL = sourceURL
        self.destinationDirectory = destinationDirectory
        self.container = container
        self.codec = codec
        self.resolution = resolution
    }
}

public struct VideoConversionResult: Sendable {
    public let sourceURL: URL
    public let outputURL: URL
    public let sourceBytes: Int64
    public let outputBytes: Int64
}

public enum VideoConversionError: Error, LocalizedError, Hashable, Sendable {
    case sourceNotReachable
    case unsupportedSettings
    case cannotCreateExporter
    case exportFailed(String)
    case commitFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .sourceNotReachable: L10n.string("video.error.source")
        case .unsupportedSettings: L10n.string("video.error.unsupported")
        case .cannotCreateExporter: L10n.string("video.error.exporter")
        case let .exportFailed(message): L10n.format("video.error.export", message)
        case let .commitFailed(message): L10n.format("video.error.commit", message)
        case .cancelled: L10n.string("error.cancelled")
        }
    }
}
