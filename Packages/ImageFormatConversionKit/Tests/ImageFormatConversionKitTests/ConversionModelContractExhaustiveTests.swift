//
//  覆盖图片、音频和视频模型公开的格式、错误及批量结果契约。
//  对全部枚举情况检查标识、能力和错误文案，并检查转换指南目录。
//  这些测试保护展示层依赖的稳定模型语义。
//  校验扩展名、无损语义、透明度能力及结果标识等展示层契约。
//  输入由测试直接构造，不依赖媒体文件或网络。
//

import Foundation
import Testing
@testable import ImageFormatConversionKit

/// 检查转换模型和指南目录的完整性与公开契约。
@Suite("Conversion model contracts")
struct ConversionModelContractExhaustiveTests {
    /// 验证音频输出格式的扩展名顺序、输入支持及有损与无损标记。
    @Test("Audio output formats expose stable extensions and lossless semantics")
    func audioFormatMetadataIsComplete() {
        #expect(AudioConversionEngine.supportedInputExtensions.contains("flac"))
        #expect(AudioOutputFormat.allCases.map { $0.fileExtension } == ["mp3", "m4a", "aac", "m4a", "wav", "aiff", "caf", "caf"])
        #expect(AudioOutputFormat.mp3.isLossless == false)
        #expect(AudioOutputFormat.aac.isLossless == false)
        #expect(AudioOutputFormat.aacFile.isLossless == false)
        #expect(AudioOutputFormat.allCases.dropFirst(3).allSatisfy { $0.isLossless })
    }

    /// 所有音频转换错误都需要非空描述，供界面显示具体失败原因。
    @Test("Audio conversion errors always provide localized descriptions")
    func audioErrorsHaveDescriptions() {
        let errors: [AudioConversionError] = [
            .sourceUnavailable,
            .unsupportedInput,
            .invalidAudio,
            .videoHasNoAudio,
            .protectedVideo,
            .cannotCreateOutput("output"),
            .conversionFailed("conversion"),
            .commitFailed("commit"),
            .cancelled
        ]

        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    /// 检查视频容器扩展名、枚举身份以及全部错误的展示文案。
    @Test("Video enum metadata and error descriptions are exhaustive")
    func videoMetadataIsComplete() {
        #expect(VideoOutputContainer.allCases.map { $0.fileExtension } == ["mp4", "mov", "m4v"])
        #expect(VideoOutputContainer.allCases.map { $0.id } == VideoOutputContainer.allCases)
        #expect(VideoCodec.allCases.map { $0.id } == VideoCodec.allCases)
        #expect(VideoResolutionPreset.allCases.map { $0.id } == VideoResolutionPreset.allCases)

        let errors: [VideoConversionError] = [
            .sourceNotReachable,
            .unsupportedSettings,
            .cannotCreateExporter,
            .exportFailed("export"),
            .commitFailed("commit"),
            .cancelled
        ]
        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    /// 图片格式的扩展名应唯一，质量和透明度能力应与支持列表一致。
    @Test("Image output formats expose unique identifiers and capability flags")
    func imageFormatMetadataIsComplete() {
        let formats = ImageOutputFormat.allCases
        #expect(Set(formats.map { $0.fileExtension }).count == formats.count)
        #expect(formats.allSatisfy { !$0.typeIdentifier.isEmpty })
        #expect(formats.filter { $0.supportsQuality } == [.jpeg, .heic, .heif, .webp])
        #expect(formats.filter { $0.requiresOpaquePixels } == [.jpeg, .bmp])
    }

    /// 包含输入、输出、参数、提交和取消在内的图片错误均可向用户解释。
    @Test("Every image conversion error has a non-empty description")
    func imageErrorsHaveDescriptions() {
        let source = URL(fileURLWithPath: "/tmp/image.png")
        let errors: [ImageConversionError] = [
            .sourceNotReachable(source),
            .cannotOpenSource(source),
            .unsupportedInputFormat(source),
            .invalidImageProperties(source),
            .animatedImageUnsupported(frameCount: 2),
            .unsupportedOutputFormat(.png),
            .invalidQuality(2),
            .invalidMaximumPixelDimension(0),
            .cannotDecode(source),
            .cannotFlattenTransparency,
            .cannotCreateDestination(source),
            .cannotFinalizeDestination(source),
            .destinationExists(source),
            .destinationBusy(source),
            .cannotReserveOutputName(source),
            .fileCommitFailed("commit"),
            .cancelled,
            .unexpected("unexpected")
        ]

        #expect(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    /// 成功项以输出地址标识、失败项以源地址标识，并保留批量进度及结果计数。
    @Test("Batch progress and conversion result identity use their output contracts")
    func batchContractsExposeStableValues() {
        let source = URL(fileURLWithPath: "/tmp/source.png")
        let output = URL(fileURLWithPath: "/tmp/output.jpg")
        let result = ImageConversionResult(
            sourceURL: source,
            outputURL: output,
            outputFormat: .jpeg,
            sourceBytes: 100,
            outputBytes: 50,
            pixelWidth: 20,
            pixelHeight: 10,
            duration: .milliseconds(10)
        )
        let progress = ImageBatchProgress(
            completed: 2,
            total: 4,
            succeeded: 1,
            failed: 1,
            lastSourceURL: source
        )
        let failure = ImageConversionFailure(sourceURL: source, error: .cancelled)
        let batch = ImageBatchConversionResult(
            successes: [result],
            failures: [failure],
            totalRequested: 2,
            wasCancelled: false
        )

        #expect(result.id == output)
        #expect(failure.id == source)
        #expect(progress.fractionCompleted == 0.5)
        #expect(batch.successes.count == 1)
        #expect(batch.failures.count == 1)
        #expect(batch.totalRequested == 2)
        #expect(batch.wasCancelled == false)
    }

    /// 图片、视频和音频指南均提供非空内容，避免展示缺失的操作说明。
    @Test("Conversion guide catalog keeps all tools actionable")
    func guideCatalogIsComplete() {
        #expect(ConversionGuideTool.allCases.count == 3)
        for tool in ConversionGuideTool.allCases {
            #expect(!tool.title.isEmpty)
            #expect(!tool.overview.isEmpty)
            #expect(!tool.purpose.isEmpty)
            #expect(!tool.importDetail.isEmpty)
            #expect(!tool.workflowDetail.isEmpty)
            #expect(!tool.imageName.isEmpty)
            #expect(!tool.symbol.isEmpty)
            #expect(!tool.importFormats.isEmpty)
            #expect(!tool.outputFormats.isEmpty)
            #expect(!tool.settings.isEmpty)
            #expect(tool == .video ? tool.codecs.count == 4 : tool.codecs.isEmpty)
        }
    }
}
