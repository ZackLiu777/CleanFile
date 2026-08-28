//
//  文件职责：定义 AudioConversion 领域使用的数据模型与状态语义。
//  所属模块：ImageFormatConversionKit。
//

import Foundation

/// 定义 `AudioSourceKind` 使用的有限状态或选项集合。
public enum AudioSourceKind: String, Codable, Sendable {
    case audioFile
    case video
}

/// 定义 `AudioOutputFormat` 使用的有限状态或选项集合。
public enum AudioOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case aac
    case aacFile
    case alac
    case wav
    case aiff
    case cafPCM
    case cafALAC

    public var id: Self { self }

    public var fileExtension: String {
        switch self {
        case .aac, .alac: "m4a"
        case .aacFile: "aac"
        case .wav: "wav"
        case .aiff: "aiff"
        case .cafPCM, .cafALAC: "caf"
        }
    }

    public var isLossless: Bool {
        switch self {
        case .aac, .aacFile: false
        case .alac, .wav, .aiff, .cafPCM, .cafALAC: true
        }
    }
}

/// 定义 `AudioBitRate` 使用的有限状态或选项集合。
public enum AudioBitRate: Int, CaseIterable, Identifiable, Sendable {
    case compact = 96_000
    case standard = 128_000
    case high = 192_000
    case veryHigh = 256_000

    public var id: Self { self }
}

/// 定义 `AudioConversionStatus` 使用的有限状态或选项集合。
public enum AudioConversionStatus: Hashable, Sendable {
    case ready
    case converting
    case completed(URL)
    case failed(String)
    case cancelled
}

/// 定义 `AudioConversionItem` 的值语义数据与相关行为。
public struct AudioConversionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let sourceBytes: Int64
    public let sourceKind: AudioSourceKind
    public let duration: TimeInterval?
    public var status: AudioConversionStatus

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceBytes: Int64,
        sourceKind: AudioSourceKind = .audioFile,
        duration: TimeInterval? = nil,
        status: AudioConversionStatus = .ready
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceBytes = sourceBytes
        self.sourceKind = sourceKind
        self.duration = duration
        self.status = status
    }
}

/// 定义 `AudioConversionRequest` 的值语义数据与相关行为。
public struct AudioConversionRequest: Sendable {
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let outputFormat: AudioOutputFormat
    public let bitRate: AudioBitRate
    public let sourceKind: AudioSourceKind

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init(
        sourceURL: URL,
        destinationDirectory: URL,
        outputFormat: AudioOutputFormat,
        bitRate: AudioBitRate,
        sourceKind: AudioSourceKind = .audioFile
    ) {
        self.sourceURL = sourceURL
        self.destinationDirectory = destinationDirectory
        self.outputFormat = outputFormat
        self.bitRate = bitRate
        self.sourceKind = sourceKind
    }
}

/// 定义 `AudioConversionError` 使用的有限状态或选项集合。
public enum AudioConversionError: Error, LocalizedError, Hashable, Sendable {
    case sourceUnavailable
    case unsupportedInput
    case invalidAudio
    case videoHasNoAudio
    case protectedVideo
    case cannotCreateOutput(String)
    case conversionFailed(String)
    case commitFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable: L10n.string("audio.error.source")
        case .unsupportedInput: L10n.string("audio.error.unsupported")
        case .invalidAudio: L10n.string("audio.error.invalid")
        case .videoHasNoAudio: L10n.string("audio.error.video_no_audio")
        case .protectedVideo: L10n.string("audio.error.video_protected")
        case let .cannotCreateOutput(message): L10n.format("audio.error.output", message)
        case let .conversionFailed(message): L10n.format("audio.error.convert", message)
        case let .commitFailed(message): L10n.format("audio.error.commit", message)
        case .cancelled: L10n.string("error.cancelled")
        }
    }
}
