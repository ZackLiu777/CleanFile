//
//  文件职责：定义 VideoConversion 领域使用的数据模型与状态语义。
//  所属模块：ImageFormatConversionKit。
//

import Foundation
import UniformTypeIdentifiers

/// 定义 `VideoOutputContainer` 使用的有限状态或选项集合。
public enum VideoOutputContainer: String, CaseIterable, Identifiable, Sendable {
    case mp4
    case mov
    case m4v

    public var id: Self { self }
    public var fileExtension: String { rawValue }
}

/// 定义 `VideoCodec` 使用的有限状态或选项集合。
public enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264
    case hevc
    case proRes422
    case proRes4444

    public var id: Self { self }
}

/// 定义 `VideoResolutionPreset` 使用的有限状态或选项集合。
public enum VideoResolutionPreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case ultraHD
    case fullHD
    case hd
    case sd

    public var id: Self { self }
}

/// 定义 `VideoConversionStatus` 使用的有限状态或选项集合。
public enum VideoConversionStatus: Hashable, Sendable {
    case ready
    case converting
    case completed(URL)
    case failed(String)
    case cancelled
}

/// 定义 `VideoConversionItem` 的值语义数据与相关行为。
public struct VideoConversionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let sourceBytes: Int64
    public var status: VideoConversionStatus

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
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

/// 定义 `VideoConversionRequest` 的值语义数据与相关行为。
public struct VideoConversionRequest: Sendable {
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let container: VideoOutputContainer
    public let codec: VideoCodec
    public let resolution: VideoResolutionPreset

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
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

/// 定义 `VideoConversionResult` 的值语义数据与相关行为。
public struct VideoConversionResult: Sendable {
    public let sourceURL: URL
    public let outputURL: URL
    public let sourceBytes: Int64
    public let outputBytes: Int64
}

/// 定义 `VideoConversionError` 使用的有限状态或选项集合。
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
