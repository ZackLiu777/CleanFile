import Foundation
import Testing
@testable import ImageFormatConversionKit

@Suite("Conversion model contracts")
struct ConversionModelContractExhaustiveTests {
    @Test("Audio output formats expose stable extensions and lossless semantics")
    func audioFormatMetadataIsComplete() {
        #expect(AudioOutputFormat.allCases.map(\.fileExtension) == ["m4a", "aac", "m4a", "wav", "aiff", "caf", "caf"])
        #expect(AudioOutputFormat.aac.isLossless == false)
        #expect(AudioOutputFormat.aacFile.isLossless == false)
        #expect(AudioOutputFormat.allCases.dropFirst(2).allSatisfy(\.isLossless))
    }

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

    @Test("Video enum metadata and error descriptions are exhaustive")
    func videoMetadataIsComplete() {
        #expect(VideoOutputContainer.allCases.map(\.fileExtension) == ["mp4", "mov", "m4v"])
        #expect(VideoOutputContainer.allCases.map(\.id) == VideoOutputContainer.allCases)
        #expect(VideoCodec.allCases.map(\.id) == VideoCodec.allCases)
        #expect(VideoResolutionPreset.allCases.map(\.id) == VideoResolutionPreset.allCases)

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

    @Test("Image output formats expose unique identifiers and capability flags")
    func imageFormatMetadataIsComplete() {
        let formats = ImageOutputFormat.allCases
        #expect(Set(formats.map(\.fileExtension)).count == formats.count)
        #expect(formats.allSatisfy { !$0.typeIdentifier.isEmpty })
        #expect(formats.filter(\.supportsQuality) == [.jpeg, .heic, .heif, .webp])
        #expect(formats.filter(\.requiresOpaquePixels) == [.jpeg, .bmp])
    }

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
