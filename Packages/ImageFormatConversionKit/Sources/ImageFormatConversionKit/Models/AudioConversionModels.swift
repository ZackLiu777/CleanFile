//
//  定义音频与视频音轨转换使用的格式、码率、请求、状态和错误。
//  列表项目保留源文件信息及可选照片资源标识，供界面展示和恢复。
//  错误描述在模型边界本地化，实际编码与文件操作由引擎负责。
//  音频引擎读取请求中的来源类型和编码参数，状态对象维护各项的处理进度。
//  输出地址仅在完成状态中出现，读取失败或取消由对应状态和错误传递。
//

import Foundation

/// 区分直接读取音频文件与先从视频提取音轨。
public enum AudioSourceKind: String, Codable, Sendable {
    case audioFile
    case video
}

/// 音频输出编码与容器；扩展名和是否无损由格式决定。
public enum AudioOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case mp3
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
        case .mp3: "mp3"
        case .aac, .alac: "m4a"
        case .aacFile: "aac"
        case .wav: "wav"
        case .aiff: "aiff"
        case .cafPCM, .cafALAC: "caf"
        }
    }

    public var isLossless: Bool {
        switch self {
        case .mp3, .aac, .aacFile: false
        case .alac, .wav, .aiff, .cafPCM, .cafALAC: true
        }
    }
}

/// 有损音频编码可选的目标码率，单位为每秒比特数。
public enum AudioBitRate: Int, CaseIterable, Identifiable, Sendable {
    case compact = 96_000
    case standard = 128_000
    case high = 192_000
    case veryHigh = 256_000
    case maximum = 320_000

    public var id: Self { self }
}

/// 提供各音频格式可选的目标码率。
extension AudioOutputFormat {
    /// 无损格式不使用目标码率；有损格式提供全部码率选项。
    var availableBitRates: [AudioBitRate] {
        isLossless ? [] : AudioBitRate.allCases
    }
}

/// 列表项状态；完成时携带输出 URL，失败时携带展示消息。
public enum AudioConversionStatus: Hashable, Sendable {
    case ready
    case converting
    case completed(URL)
    case failed(String)
    case cancelled
}

/// 音频转换列表项，包含源信息、可选音频属性及当前状态。
public struct AudioConversionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let sourceBytes: Int64
    public let sourceKind: AudioSourceKind
    public let duration: TimeInterval?
    public let sampleRate: Double?
    public let channelCount: Int?
    public var status: AudioConversionStatus
    public let photoAssetIdentifier: String?

    /// 保存音频源地址、大小、来源类型、可用媒体属性、状态和可选照片资源标识。
    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceBytes: Int64,
        sourceKind: AudioSourceKind = .audioFile,
        duration: TimeInterval? = nil,
        sampleRate: Double? = nil,
        channelCount: Int? = nil,
        status: AudioConversionStatus = .ready,
        photoAssetIdentifier: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceBytes = sourceBytes
        self.sourceKind = sourceKind
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.status = status
        self.photoAssetIdentifier = photoAssetIdentifier
    }
}

/// 交给音频引擎的输入、目标目录和编码参数。
public struct AudioConversionRequest: Sendable {
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let outputFormat: AudioOutputFormat
    public let bitRate: AudioBitRate
    public let sourceKind: AudioSourceKind

    /// 保存音频源、输出目录、输出格式、目标码率及来源类型。
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

/// 区分源不可访问、音轨不可用、编码、提交及取消等错误。
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
