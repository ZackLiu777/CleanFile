import Foundation
import Testing
@testable import ImageFormatConversionKit

@Suite("Conversion engine validation")
struct ConversionEngineValidationTests {
    @Test("Audio conversion rejects an unsupported extension before reading the source")
    func audioRejectsUnsupportedExtension() async {
        let request = AudioConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/source.txt"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/output"),
            outputFormat: .wav,
            bitRate: .standard
        )

        do {
            _ = try await AudioConversionEngine().convert(request, progress: { _ in })
            Issue.record("Expected unsupportedInput")
        } catch let error as AudioConversionError {
            #expect(error == .unsupportedInput)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Audio conversion reports an unavailable supported source")
    func audioReportsUnavailableSource() async {
        let source = URL(fileURLWithPath: "/tmp/missing-source.wav")
        let request = AudioConversionRequest(
            sourceURL: source,
            destinationDirectory: URL(fileURLWithPath: "/tmp/output"),
            outputFormat: .wav,
            bitRate: .standard
        )

        do {
            _ = try await AudioConversionEngine().convert(request, progress: { _ in })
            Issue.record("Expected sourceUnavailable")
        } catch let error as AudioConversionError {
            #expect(error == .sourceUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Video conversion rejects incompatible HEVC resolutions")
    func videoRejectsIncompatibleHEVCResolution() async {
        let request = VideoConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/missing.mov"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/output"),
            container: .mp4,
            codec: .hevc,
            resolution: .hd
        )

        do {
            _ = try await VideoConversionEngine().convert(request, progress: { _ in })
            Issue.record("Expected unsupportedSettings")
        } catch let error as VideoConversionError {
            #expect(error == .unsupportedSettings)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Video conversion rejects ProRes outside MOV at original resolution")
    func videoRejectsInvalidProResSettings() async {
        let request = VideoConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/missing.mov"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/output"),
            container: .mp4,
            codec: .proRes422,
            resolution: .fullHD
        )

        do {
            _ = try await VideoConversionEngine().convert(request, progress: { _ in })
            Issue.record("Expected unsupportedSettings")
        } catch let error as VideoConversionError {
            #expect(error == .unsupportedSettings)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Video conversion rejects M4V with non-H264 codecs")
    func videoRejectsM4VWithNonH264Codec() async {
        let request = VideoConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/missing.mov"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/output"),
            container: .m4v,
            codec: .hevc,
            resolution: .original
        )

        do {
            _ = try await VideoConversionEngine().convert(request, progress: { _ in })
            Issue.record("Expected unsupportedSettings")
        } catch let error as VideoConversionError {
            #expect(error == .unsupportedSettings)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Video conversion reports an unavailable source after valid settings")
    func videoReportsUnavailableSource() async {
        let request = VideoConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/missing.mov"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/output"),
            container: .mov,
            codec: .h264,
            resolution: .original
        )

        do {
            _ = try await VideoConversionEngine().convert(request, progress: { _ in })
            Issue.record("Expected sourceNotReachable")
        } catch let error as VideoConversionError {
            #expect(error == .sourceNotReachable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
