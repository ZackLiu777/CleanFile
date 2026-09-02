//
//  文件职责：实现 AudioConversion 底层处理流程，并向上层提供稳定入口。
//  所属模块：ImageFormatConversionKit。
//

import AVFAudio
import AVFoundation
import AudioToolbox
import Foundation

/// 使用 Actor 隔离 `AudioConversionEngine` 的可变状态，确保并发访问安全。
public actor AudioConversionEngine {
    public static let supportedInputExtensions = ["m4a", "aac", "mp3", "wav", "aiff", "aif", "caf"]
    public static let supportedVideoInputExtensions = ["mov", "mp4", "m4v"]

    private let videoExtractor = VideoAudioExtractionEngine()

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    public init() {}

    /// 执行 `inspect` 分析流程，在遵守文件访问边界的前提下生成结果。
    public func inspect(_ sourceURL: URL, sourceKind: AudioSourceKind) async throws -> TimeInterval {
        switch sourceKind {
        case .audioFile:
            let file = try AVAudioFile(forReading: sourceURL)
            let sampleRate = file.processingFormat.sampleRate
            return sampleRate > 0 ? Double(file.length) / sampleRate : 0
        case .video:
            return try await videoExtractor.inspect(sourceURL)
        }
    }

    /// 执行 `convert` 转换流程，并按当前配置生成输出结果。
    public func convert(
        _ request: AudioConversionRequest,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        let performanceID = ConversionPerformance.begin("Conversion Audio Total")
        defer { ConversionPerformance.end("Conversion Audio Total", id: performanceID) }
        let source = request.sourceURL.standardizedFileURL
        let directory = request.destinationDirectory.standardizedFileURL
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let directoryAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if directoryAccess { directory.stopAccessingSecurityScopedResource() }
        }

        let supportedExtensions = request.sourceKind == .video
            ? Self.supportedVideoInputExtensions
            : Self.supportedInputExtensions
        guard supportedExtensions.contains(source.pathExtension.lowercased()) else {
            throw AudioConversionError.unsupportedInput
        }
        guard (try? source.checkResourceIsReachable()) == true else {
            throw AudioConversionError.sourceUnavailable
        }

        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory
            .appendingPathComponent(".audio-conversion-\(UUID().uuidString)")
            .appendingPathExtension(request.outputFormat.fileExtension)
        let output = uniqueDestination(
            source: source,
            directory: directory,
            extension: request.outputFormat.fileExtension
        )
        defer { try? manager.removeItem(at: temporary) }

        let conversionSource: URL
        let extractedPCM: URL?
        if request.sourceKind == .video {
            let extracted = directory
                .appendingPathComponent(".video-audio-\(UUID().uuidString)")
                .appendingPathExtension("caf")
            extractedPCM = extracted
            do {
                try await videoExtractor.extractPCM(from: source, to: extracted) { value in
                    await progress(value * 0.55)
                }
            } catch let error as AudioConversionError {
                throw error
            } catch {
                throw AudioConversionError.conversionFailed(error.localizedDescription)
            }
            conversionSource = extracted
        } else {
            extractedPCM = nil
            conversionSource = source
        }
        defer {
            if let extractedPCM { try? manager.removeItem(at: extractedPCM) }
        }

        let encodeID = ConversionPerformance.begin("Conversion Audio Encode")
        do {
            let input = try AVAudioFile(forReading: conversionSource)
            let inputFormat = input.processingFormat
            guard input.length > 0, inputFormat.channelCount > 0 else {
                throw AudioConversionError.invalidAudio
            }

            let settings = outputSettings(
                request.outputFormat,
                bitRate: request.bitRate,
                sampleRate: inputFormat.sampleRate,
                channels: inputFormat.channelCount
            )
            let outputFile = try AVAudioFile(
                forWriting: temporary,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            guard let converter = AVAudioConverter(
                from: inputFormat,
                to: outputFile.processingFormat
            ) else {
                throw AudioConversionError.invalidAudio
            }

            let capacity: AVAudioFrameCount = 16_384
            while input.framePosition < input.length {
                try Task.checkCancellation()
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFile.processingFormat,
                    frameCapacity: capacity
                ) else {
                    throw AudioConversionError.invalidAudio
                }

                let inputSupply = AudioInputSupply()
                var conversionError: NSError?
                let status = converter.convert(to: outputBuffer, error: &conversionError) { _, state in
                    guard inputSupply.claim() else {
                        state.pointee = .noDataNow
                        return nil
                    }
                    guard let inputBuffer = AVAudioPCMBuffer(
                        pcmFormat: inputFormat,
                        frameCapacity: capacity
                    ) else {
                        state.pointee = .noDataNow
                        return nil
                    }
                    do {
                        try input.read(into: inputBuffer, frameCount: capacity)
                        state.pointee = inputBuffer.frameLength == 0 ? .endOfStream : .haveData
                        return inputBuffer
                    } catch {
                        state.pointee = .noDataNow
                        return nil
                    }
                }

                if let conversionError {
                    throw AudioConversionError.conversionFailed(conversionError.localizedDescription)
                }
                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }
                let encodingProgress = Double(input.framePosition) / Double(input.length)
                let overallProgress = request.sourceKind == .video
                    ? 0.55 + encodingProgress * 0.45
                    : encodingProgress
                await progress(overallProgress)
                if status == .endOfStream { break }
            }
        } catch is CancellationError {
            ConversionPerformance.end("Conversion Audio Encode", id: encodeID)
            throw AudioConversionError.cancelled
        } catch let error as AudioConversionError {
            ConversionPerformance.end("Conversion Audio Encode", id: encodeID)
            throw error
        } catch {
            ConversionPerformance.end("Conversion Audio Encode", id: encodeID)
            throw AudioConversionError.conversionFailed(error.localizedDescription)
        }
        ConversionPerformance.end("Conversion Audio Encode", id: encodeID)

        try Task.checkCancellation()
        let commitID = ConversionPerformance.begin("Conversion Output Commit")
        defer { ConversionPerformance.end("Conversion Output Commit", id: commitID) }
        do {
            try manager.moveItem(at: temporary, to: output)
        } catch {
            throw AudioConversionError.commitFailed(error.localizedDescription)
        }
        await progress(1)
        return output
    }

    /// 取消 `cancelAll` 对应的进行中任务，并收敛到可继续操作的状态。
    public func cancelAll() async {
        await videoExtractor.cancelAll()
    }

    /// 封装 `outputSettings` 对应的局部行为，供当前类型在统一入口下复用。
    private func outputSettings(
        _ format: AudioOutputFormat,
        bitRate: AudioBitRate,
        sampleRate: Double,
        channels: AVAudioChannelCount
    ) -> [String: Any] {
        let channelCount = Int(min(max(channels, 1), 2))
        switch format {
        case .aac, .aacFile:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: bitRate.rawValue
            ]
        case .alac, .cafALAC:
            return [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount
            ]
        case .wav:
            return pcmSettings(
                sampleRate: sampleRate,
                channelCount: channelCount,
                isBigEndian: false
            )
        case .aiff:
            return pcmSettings(
                sampleRate: sampleRate,
                channelCount: channelCount,
                isBigEndian: true
            )
        case .cafPCM:
            return pcmSettings(
                sampleRate: sampleRate,
                channelCount: channelCount,
                isBigEndian: false
            )
        }
    }

    /// 封装 `pcmSettings` 对应的局部行为，供当前类型在统一入口下复用。
    private func pcmSettings(
        sampleRate: Double,
        channelCount: Int,
        isBigEndian: Bool
    ) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: isBigEndian,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    /// 封装 `uniqueDestination` 对应的局部行为，供当前类型在统一入口下复用。
    private func uniqueDestination(source: URL, directory: URL, extension ext: String) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        for suffix in 0 ... 9_999 {
            let name = suffix == 0 ? base : "\(base)-\(suffix)"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
}

/// `AVAudioConverter` may invoke its input block from concurrently executing
/// code. A locked one-shot state preserves the existing per-conversion-call
/// supply rule without capturing mutable local variables.
private final class AudioInputSupply: @unchecked Sendable {
    private let lock = NSLock()
    private var isAvailable = true

    func claim() -> Bool {
        lock.withLock {
            guard isAvailable else { return false }
            isAvailable = false
            return true
        }
    }
}
