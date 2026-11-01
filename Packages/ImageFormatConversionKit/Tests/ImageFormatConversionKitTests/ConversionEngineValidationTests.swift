//
//  验证音频和视频引擎在转换前拒绝不支持的输入及配置。
//  覆盖扩展名、源文件缺失以及视频容器、编码器和分辨率组合。
//  断言对应错误，避免无效请求进入后续编码流程。
//  无效配置与不可读取的示例来源分别检查，避免把参数错误误报为文件错误。
//  验证主要发生在编码之前，不需要用户媒体。
//

import Foundation
import Testing
@testable import ImageFormatConversionKit

/// 覆盖音频源和视频导出配置的前置错误。
@Suite("Conversion engine validation")
struct ConversionEngineValidationTests {
    /// 对不存在的文本源先报告格式不受支持，确认扩展名校验先于文件读取。
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

    /// 扩展名受支持但文件不存在时，应区分为源文件不可用。
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

    /// HEVC 与不支持的分辨率组合应在读取缺失源文件之前被拒绝。
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

    /// ProRes 配置与容器、分辨率约束冲突时返回配置错误。
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

    /// M4V 与 HEVC 的组合不受支持，应返回配置错误。
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

    /// 设置有效时，缺失的视频源应报告无法访问而非配置错误。
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
