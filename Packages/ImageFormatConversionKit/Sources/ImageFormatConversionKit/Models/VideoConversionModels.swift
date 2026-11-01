//
//  定义视频转换的容器、编码、分辨率、请求、结果和错误。
//  请求可选择系统预设或自定义码率，并可保留 Live Photo 所需的时间元数据。
//  列表状态与源资源信息由调用方维护，模型本身不执行文件操作。
//  视频状态对象构造请求并展示各项转换状态，视频引擎使用配置执行导出。
//  类型描述目标容器和编码选项，不保证每种组合都受当前设备或源媒体支持。
//

import Foundation
import UniformTypeIdentifiers

/// 视频输出容器；扩展名与原始值一致。
public enum VideoOutputContainer: String, CaseIterable, Identifiable, Sendable {
    case mp4
    case mov
    case m4v

    public var id: Self { self }
    public var fileExtension: String { rawValue }
}

/// 视频转换可请求的 H.264、HEVC 和 ProRes 编码。
public enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264
    case hevc
    case proRes422
    case proRes4444

    public var id: Self { self }
}

/// 视频导出可选分辨率；实际支持情况由引擎验证。
public enum VideoResolutionPreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case ultraHD
    case fullHD
    case hd
    case sd

    public var id: Self { self }
}

/// 列表项状态；完成时携带输出 URL，失败时携带展示消息。
public enum VideoConversionStatus: Hashable, Sendable {
    case ready
    case converting
    case completed(URL)
    case failed(String)
    case cancelled
}

/// 视频列表项关联源文件、字节数、状态及可选照片资源标识。
public struct VideoConversionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let sourceBytes: Int64
    public var status: VideoConversionStatus
    public internal(set) var photoAssetIdentifier: String?

    /// 保存视频源地址、文件大小、当前状态及可选照片资源标识。
    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceBytes: Int64,
        status: VideoConversionStatus = .ready,
        photoAssetIdentifier: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceBytes = sourceBytes
        self.status = status
        self.photoAssetIdentifier = photoAssetIdentifier
    }
}

/// 交给视频引擎的源、目标和导出配置；引擎负责验证组合。
public struct VideoConversionRequest: Sendable {
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let container: VideoOutputContainer
    public let codec: VideoCodec
    public let resolution: VideoResolutionPreset
    /// Nil keeps the existing system export preset. A value below 1 requests
    /// a fraction of the source video's bit rate through the explicit encoder.
    public let bitRateFraction: Double?
    /// Preserve global and timed metadata when compressing a paired Live Photo movie.
    public let preservesTimedMetadata: Bool

    /// 保存输入输出位置、容器、编码器、分辨率、码率比例及定时元数据选项。
    public init(
        sourceURL: URL,
        destinationDirectory: URL,
        container: VideoOutputContainer,
        codec: VideoCodec,
        resolution: VideoResolutionPreset,
        bitRateFraction: Double? = nil,
        preservesTimedMetadata: Bool = false
    ) {
        self.sourceURL = sourceURL
        self.destinationDirectory = destinationDirectory
        self.container = container
        self.codec = codec
        self.resolution = resolution
        self.bitRateFraction = bitRateFraction
        self.preservesTimedMetadata = preservesTimedMetadata
    }
}

/// 成功导出后的源与输出路径及各自字节数。
public struct VideoConversionResult: Sendable {
    public let sourceURL: URL
    public let outputURL: URL
    public let sourceBytes: Int64
    public let outputBytes: Int64
}

/// 区分设置不支持、HDR 限制、导出、提交和取消等错误。
public enum VideoConversionError: Error, LocalizedError, Hashable, Sendable {
    case sourceNotReachable
    case unsupportedSettings
    case hdrBitrateUnsupported
    case cannotCreateExporter
    case exportFailed(String)
    case commitFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .sourceNotReachable: L10n.string("video.error.source")
        case .unsupportedSettings: L10n.string("video.error.unsupported")
        case .hdrBitrateUnsupported: L10n.string("video.error.hdr_bitrate")
        case .cannotCreateExporter: L10n.string("video.error.exporter")
        case let .exportFailed(message): L10n.format("video.error.export", message)
        case let .commitFailed(message): L10n.format("video.error.commit", message)
        case .cancelled: L10n.string("error.cancelled")
        }
    }
}
