import AVFAudio
import AudioToolbox
import Foundation

// The standalone harness compiles the production audio engine directly, outside
// SwiftPM's resource bundle. Error text is irrelevant to its assertions.
enum L10n {
    static func string(_ key: String.LocalizationValue) -> String { String(localized: key) }
    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: String(localized: key), arguments: arguments)
    }
}

@main
struct ConversionStressHarness {
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

    private static func report(_ format: String, _ values: [Double], mediaSeconds: Int) {
        let sorted = values.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let realtime = Double(mediaSeconds) / (median / 1_000)
        print("STRESS_SUMMARY format=\(format) samples=\(values.count) median_ms=\(median) p95_ms=\(p95) min_ms=\(sorted[0]) max_ms=\(sorted.last!) realtime_factor=\(realtime)")
    }

    private static func elapsedMilliseconds(from start: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: .now).components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    private static func peakRSSMiB() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return Double(usage.ru_maxrss) / 1_048_576
    }
}

private actor ProgressAudit {
    private var last = 0.0
    private var monotonic = true
    private var count = 0

    func record(_ value: Double) {
        monotonic = monotonic && value >= last && (0 ... 1).contains(value)
        last = value
        count += 1
    }

    var result: (last: Double, count: Int, isMonotonic: Bool) {
        (last, count, monotonic)
    }
}

private enum HarnessError: Error {
    case fixtureCreationFailed
    case invalidProgress
    case invalidDuration(Double)
    case emptyOutput
    case invalidInputAccepted
    case cancellationIgnored
    case temporaryFilesRemain
}
