//
//  独立压力工具使用合成 PCM 音频反复执行 MP3 转换并记录耗时。
//  每轮检查输出时长、非空文件和进度，同时检查无效输入与取消清理。
//  素材和输出位于临时目录，结束时清理；工具不会自动作为测试运行。
//  使用固定长度的音频素材重复测量，并对输出和进度做正确性检查。
//  这是独立可执行入口，结果依赖实际运行环境，不代表正式测试结果。
//

import AVFAudio
import AudioToolbox
import Foundation

// The standalone harness compiles the production audio engine directly, outside
// SwiftPM's resource bundle. Error text is irrelevant to its assertions.
/// 独立构建不包含资源包，使用轻量文本入口满足引擎依赖。
enum L10n {
    /// 按当前本地化环境解析压力工具使用的字符串键。
    static func string(_ key: String.LocalizationValue) -> String { String(localized: key) }
    /// 解析本地化格式字符串并使用调用方提供的参数格式化。
    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: String(localized: key), arguments: arguments)
    }
}

/// 执行多轮合成音频转换，验证结果并报告延迟和峰值内存。
@main
struct ConversionStressHarness {
    /// 创建临时素材，执行多轮转换和错误检查，退出时清理整个目录。
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanFile-Conversion-Stress-\(UUID().uuidString)")
        let outputs = root.appendingPathComponent("Outputs")
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let duration = 180
        let rounds = 24
        let wav = root.appendingPathComponent("stress-\(duration)s.wav")
        try writeFixture(to: wav, durationSeconds: duration)

        print("STRESS_CONFIG duration_seconds=\(duration) rounds=\(rounds)")

        var mp3Samples: [Double] = []
        for round in 0 ..< rounds {
            mp3Samples.append(try await convert(
                source: wav,
                output: outputs,
                format: .mp3,
                duration: duration,
                round: round
            ))
        }

        try await validateInvalidInput(root: root, outputs: outputs)
        try await validateCancellation(source: wav, outputs: outputs)
        report("mp3", mp3Samples, mediaSeconds: duration)
        print("STRESS_RESULT status=passed peak_rss_mib=\(peakRSSMiB())")
    }

    /// 转换一次并检查进度、解码时长及输出大小，返回耗时。
    private static func convert(
        source: URL,
        output: URL,
        format: AudioOutputFormat,
        duration: Int,
        round: Int
    ) async throws -> Double {
        let progress = ProgressAudit()
        let started = ContinuousClock.now
        let result = try await AudioConversionEngine().convert(
            AudioConversionRequest(
                sourceURL: source,
                destinationDirectory: output,
                outputFormat: format,
                bitRate: .high
            )
        ) { value in
            await progress.record(value)
        }
        let milliseconds = elapsedMilliseconds(from: started)
        let audit = await progress.result
        guard audit.isMonotonic, audit.last == 1 else {
            throw HarnessError.invalidProgress
        }
        let decoded = try AVAudioFile(forReading: result)
        let decodedDuration = Double(decoded.length) / decoded.processingFormat.sampleRate
        guard abs(decodedDuration - Double(duration)) < 0.25 else {
            throw HarnessError.invalidDuration(decodedDuration)
        }
        let bytes = try result.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0 else { throw HarnessError.emptyOutput }
        print("STRESS_SAMPLE format=\(format.rawValue) round=\(round) input=\(source.pathExtension) duration_ms=\(milliseconds) output_bytes=\(bytes) progress_updates=\(audit.count)")
        return milliseconds
    }

    /// 确认不支持的输入类型被引擎拒绝。
    private static func validateInvalidInput(root: URL, outputs: URL) async throws {
        let invalid = root.appendingPathComponent("invalid.txt")
        try Data("not audio".utf8).write(to: invalid)
        do {
            _ = try await AudioConversionEngine().convert(
                AudioConversionRequest(
                    sourceURL: invalid,
                    destinationDirectory: outputs,
                    outputFormat: .mp3,
                    bitRate: .standard
                )
            ) { _ in }
            throw HarnessError.invalidInputAccepted
        } catch AudioConversionError.unsupportedInput {
            print("STRESS_CHECK invalid_input=passed")
        }
    }

    /// 取消转换并检查未留下音频转换临时文件。
    private static func validateCancellation(source: URL, outputs: URL) async throws {
        let task = Task {
            try await AudioConversionEngine().convert(
                AudioConversionRequest(
                    sourceURL: source,
                    destinationDirectory: outputs,
                    outputFormat: .mp3,
                    bitRate: .veryHigh
                )
            ) { _ in }
        }
        task.cancel()
        do {
            _ = try await task.value
            throw HarnessError.cancellationIgnored
        } catch AudioConversionError.cancelled {
            let leftovers = try FileManager.default.contentsOfDirectory(
                at: outputs,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(".audio-conversion-") }
            guard leftovers.isEmpty else { throw HarnessError.temporaryFilesRemain }
            print("STRESS_CHECK cancellation=passed")
        }
    }

    /// 分块生成确定性文件，供实验或压力转换使用。
    private static func writeFixture(to url: URL, durationSeconds: Int) throws {
        let sampleRate = 44_100.0
        let channels: AVAudioChannelCount = 2
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = file.processingFormat
        let totalFrames = AVAudioFramePosition(sampleRate * Double(durationSeconds))
        let chunk: AVAudioFrameCount = 16_384
        var written: AVAudioFramePosition = 0
        while written < totalFrames {
            let count = AVAudioFrameCount(min(AVAudioFramePosition(chunk), totalFrames - written))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  let channelData = buffer.floatChannelData
            else { throw HarnessError.fixtureCreationFailed }
            buffer.frameLength = count
            for channel in 0 ..< Int(channels) {
                for frame in 0 ..< Int(count) {
                    let position = Double(written + AVAudioFramePosition(frame))
                    channelData[channel][frame] = Float(sin(2 * .pi * 440 * position / sampleRate) * 0.2)
                }
            }
            try file.write(from: buffer)
            written += AVAudioFramePosition(count)
        }
    }

    /// 汇总样本中位数、P95 和实时倍率，便于比较不同运行。
    private static func report(_ format: String, _ values: [Double], mediaSeconds: Int) {
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let realtime = Double(mediaSeconds) / (median / 1_000)
        print("STRESS_SUMMARY format=\(format) samples=\(values.count) median_ms=\(median) p95_ms=\(p95) min_ms=\(sorted[0]) max_ms=\(sorted.last!) realtime_factor=\(realtime)")
    }

    /// 计算从指定时刻到现在的毫秒数。
    private static func elapsedMilliseconds(from start: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: .now).components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    /// 读取当前进程峰值常驻内存并转换为 MiB。
    private static func peakRSSMiB() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return Double(usage.ru_maxrss) / 1_048_576
    }
}

/// 串行记录回调次数，并检查进度位于有效范围且不倒退。
private actor ProgressAudit {
    private var last = 0.0
    private var monotonic = true
    private var count = 0

    /// 更新最近进度并累计是否始终符合单调约束。
    func record(_ value: Double) {
        monotonic = monotonic && value >= last && (0 ... 1).contains(value)
        last = value
        count += 1
    }

    var result: (last: Double, count: Int, isMonotonic: Bool) {
        (last, count, monotonic)
    }
}

/// 压力工具验证失败时用于区分具体原因。
private enum HarnessError: Error {
    case fixtureCreationFailed
    case invalidProgress
    case invalidDuration(Double)
    case emptyOutput
    case invalidInputAccepted
    case cancellationIgnored
    case temporaryFilesRemain
}
