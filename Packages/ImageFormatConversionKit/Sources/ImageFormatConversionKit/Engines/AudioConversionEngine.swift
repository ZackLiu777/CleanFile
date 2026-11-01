//
//  音频转换入口使用 AVFoundation 处理系统支持的格式，并以 LAME 流式编码 MP3。
//  视频输入先提取 PCM，再编码为目标格式；进度按两个阶段合并。
//  输出先写入临时文件，编码完成后才提交，访问权限和临时资源在结束时释放。
//  音频 ViewModel 通过此入口检查输入及启动转换，视频音轨由专门的提取器处理。
//  进度经合并与节流后交给调用方；异常或取消不应留下未提交的输出。
//

import AVFAudio
import AVFoundation
import AudioToolbox
import Foundation
import LAME

/// 协调音频文件或视频音轨的检查、编码及中间文件清理。
public actor AudioConversionEngine {
    /// 检查得到的时长、采样率和声道数；视频输入使用提取路径的默认音频参数。
    public struct Inspection: Sendable {
        public let duration: TimeInterval
        public let sampleRate: Double
        public let channelCount: Int
    }
    public static let supportedInputExtensions = ["m4a", "aac", "mp3", "flac", "wav", "aiff", "aif", "caf"]
    public static let supportedVideoInputExtensions = ["mov", "mp4", "m4v"]

    private let videoExtractor = VideoAudioExtractionEngine()

    /// 创建使用系统媒体框架的音频转换引擎；初始化时不读取文件。
    public init() {}

    /// 返回可用时长；视频检查会拒绝受保护或没有音轨的媒体。
    public func inspect(_ sourceURL: URL, sourceKind: AudioSourceKind) async throws -> TimeInterval {
        try await inspectDetails(sourceURL, sourceKind: sourceKind).duration
    }

    /// 检查音频处理格式，或检查视频是否包含可提取音轨。
    public func inspectDetails(_ sourceURL: URL, sourceKind: AudioSourceKind) async throws -> Inspection {
        switch sourceKind {
        case .audioFile:
            let file = try AVAudioFile(forReading: sourceURL)
            let format = file.processingFormat
            let duration = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0
            return Inspection(
                duration: duration,
                sampleRate: format.sampleRate,
                channelCount: Int(format.channelCount)
            )
        case .video:
            return Inspection(
                duration: try await videoExtractor.inspect(sourceURL),
                sampleRate: 48_000,
                channelCount: 2
            )
        }
    }

    /// 分块转换音频，成功后提交临时文件；视频输入先提取 PCM。
    /// 源文件和目标目录的安全范围访问覆盖整个转换，失败时清理临时文件。
    public func convert(
        _ request: AudioConversionRequest,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        let performanceID = ConversionPerformance.begin("Conversion Audio Total")
        defer { ConversionPerformance.end("Conversion Audio Total", id: performanceID) }
        let progressReporter = ConversionProgressReporter(callback: progress)
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
                    await progressReporter.report(value * 0.55)
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

            if request.outputFormat == .mp3 {
                try await encodeMP3(
                    input: input,
                    bitRate: request.bitRate,
                    destination: temporary,
                    sourceKind: request.sourceKind,
                    progressReporter: progressReporter
                )
                ConversionPerformance.end("Conversion Audio Encode", id: encodeID)
                try Task.checkCancellation()
                do {
                    try manager.moveItem(at: temporary, to: output)
                } catch {
                    throw AudioConversionError.commitFailed(error.localizedDescription)
                }
                await progressReporter.report(1, force: true)
                return output
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
                await progressReporter.report(overallProgress)
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
        await progressReporter.report(1, force: true)
        return output
    }

    /// 请求停止进行中的视频音轨提取；音频编码依靠调用任务的取消检查停止。
    public func cancelAll() async {
        await videoExtractor.cancelAll()
    }

    /// 将输出格式映射为系统编码设置，并将声道限制为一至两声道。
    private func outputSettings(
        _ format: AudioOutputFormat,
        bitRate: AudioBitRate,
        sampleRate: Double,
        channels: AVAudioChannelCount
    ) -> [String: Any] {
        let channelCount = Int(min(max(channels, 1), 2))
        switch format {
        case .mp3:
            return [:]
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

    /// 分块向 LAME 输入 PCM，写入编码数据并在结束时刷新编码器。
    /// 每块之间检查取消；资源由 defer 释放，避免将整段音频载入内存。
    private func encodeMP3(
        input: AVAudioFile,
        bitRate: AudioBitRate,
        destination: URL,
        sourceKind: AudioSourceKind,
        progressReporter: ConversionProgressReporter
    ) async throws {
        let format = input.processingFormat
        let channelCount = Int(format.channelCount)
        guard (1 ... 2).contains(channelCount), format.sampleRate > 0 else {
            throw AudioConversionError.invalidAudio
        }
        guard let encoder = lame_init() else {
            throw AudioConversionError.conversionFailed("LAME initialization failed")
        }
        defer { lame_close(encoder) }

        guard lame_set_in_samplerate(encoder, Int32(format.sampleRate.rounded())) == 0,
              lame_set_num_channels(encoder, Int32(channelCount)) == 0,
              lame_set_brate(encoder, Int32(bitRate.rawValue / 1_000)) == 0,
              lame_set_quality(encoder, 2) == 0,
              lame_init_params(encoder) == 0
        else {
            throw AudioConversionError.conversionFailed("LAME configuration failed")
        }

        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw AudioConversionError.cannotCreateOutput(destination.lastPathComponent)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let capacity: AVAudioFrameCount = 16_384
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioConversionError.invalidAudio
        }
        var encoded = [UInt8](repeating: 0, count: Int(Double(capacity) * 1.25) + 7_200)

        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: pcm, frameCount: capacity)
            guard pcm.frameLength > 0, let channels = pcm.floatChannelData else { break }

            let sampleCount = Int32(pcm.frameLength)
            let encodedCount = encoded.withUnsafeMutableBufferPointer { outputBuffer in
                lame_encode_buffer_ieee_float(
                    encoder,
                    channels[0],
                    channelCount == 2 ? channels[1] : channels[0],
                    sampleCount,
                    outputBuffer.baseAddress,
                    Int32(outputBuffer.count)
                )
            }
            guard encodedCount >= 0 else {
                throw AudioConversionError.conversionFailed("LAME encoding failed (\(encodedCount))")
            }
            if encodedCount > 0 {
                try handle.write(contentsOf: Data(encoded.prefix(Int(encodedCount))))
            }

            let encodingProgress = Double(input.framePosition) / Double(input.length)
            let overallProgress = sourceKind == .video
                ? 0.55 + encodingProgress * 0.45
                : encodingProgress
            await progressReporter.report(overallProgress)
        }

        var flushed = [UInt8](repeating: 0, count: 7_200)
        let flushedCount = flushed.withUnsafeMutableBufferPointer {
            lame_encode_flush(encoder, $0.baseAddress, Int32($0.count))
        }
        guard flushedCount >= 0 else {
            throw AudioConversionError.conversionFailed("LAME flush failed (\(flushedCount))")
        }
        if flushedCount > 0 {
            try handle.write(contentsOf: Data(flushed.prefix(Int(flushedCount))))
        }
    }

    /// 生成 16 位交错 PCM 设置；字节序由目标容器决定。
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

    /// 按递增后缀寻找未占用文件名，耗尽候选后使用 UUID。
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

    /// 每次转换调用只允许一次输入供应，锁用于保护并发回调中的状态。
    func claim() -> Bool {
        lock.withLock {
            guard isAvailable else { return false }
            isAvailable = false
            return true
        }
    }
}
