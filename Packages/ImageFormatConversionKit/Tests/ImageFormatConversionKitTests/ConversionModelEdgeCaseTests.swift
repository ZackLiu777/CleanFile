import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import ImageFormatConversionKit

@Suite("Conversion model edge cases")
struct ConversionModelEdgeCaseTests {
    @Test("Image output formats expose unique, non-empty extensions")
    func imageOutputFormatsHaveStableExtensions() {
        let extensions = ImageOutputFormat.allCases.map(\.fileExtension)

        #expect(extensions.allSatisfy { !$0.isEmpty })
        #expect(Set(extensions).count == extensions.count)
        #expect(ImageOutputFormat.jpeg.fileExtension == "jpg")
    }

    @Test("Quality support and transparency requirements match format capabilities")
    func imageFormatCapabilitiesAreExplicit() {
        #expect(ImageOutputFormat.jpeg.supportsQuality)
        #expect(ImageOutputFormat.heic.supportsQuality)
        #expect(ImageOutputFormat.webp.supportsQuality)
        #expect(!ImageOutputFormat.png.supportsQuality)
        #expect(ImageOutputFormat.jpeg.requiresOpaquePixels)
        #expect(ImageOutputFormat.bmp.requiresOpaquePixels)
        #expect(!ImageOutputFormat.png.requiresOpaquePixels)
    }

    @Test("Flatten colors clamp infinities and NaN to safe values")
    func flattenColorClampsNonFiniteValues() {
        let color = ImageFlattenColor(red: -.infinity, green: .infinity, blue: .nan)

        #expect(color.red == 0)
        #expect(color.green == 0)
        #expect(color.blue == 0)
    }

    @Test("Resize presets map to original or bounded fit policies")
    func resizePresetsMapToPolicies() {
        #expect(ImageResizePreset.original.policy == .original)
        #expect(ImageResizePreset.ultraHD.policy == .fit(maxPixelDimension: 4_096))
        #expect(ImageResizePreset.large.policy == .fit(maxPixelDimension: 2_048))
        #expect(ImageResizePreset.medium.policy == .fit(maxPixelDimension: 1_280))
    }

    @Test("Conversion progress clamps fractions and percentages to completion")
    func importProgressClampsFractions() {
        let beforeStart = ConversionImportProgress(
            completed: -2,
            total: 4,
            currentFileName: "input.png",
            currentFileFraction: -1
        )
        let pastEnd = ConversionImportProgress(
            completed: 10,
            total: 4,
            currentFileName: "input.png",
            currentFileFraction: 10
        )

        #expect(beforeStart.fractionCompleted == 0)
        #expect(beforeStart.percentage == 0)
        #expect(pastEnd.fractionCompleted == 1)
        #expect(pastEnd.percentage == 100)
    }

    @Test("Zero-total progress remains zero and maps safely into a range")
    func emptyImportProgressIsSafe() {
        let empty = ConversionImportProgress(completed: 0, total: 0, currentFileName: nil)
        let mapped = empty.mapped(to: -0.5 ... 2)

        #expect(empty.fractionCompleted == 0)
        #expect(empty.percentage == 0)
        #expect(mapped.total == 1)
        #expect(mapped.fractionCompleted == 0)
    }

    @Test("Audio formats expose lossless semantics and expected extensions")
    func audioFormatMetadataIsStable() {
        #expect(AudioOutputFormat.aac.fileExtension == "m4a")
        #expect(AudioOutputFormat.aacFile.fileExtension == "aac")
        #expect(AudioOutputFormat.cafPCM.fileExtension == "caf")
        #expect(!AudioOutputFormat.aac.isLossless)
        #expect(AudioOutputFormat.alac.isLossless)
        #expect(AudioOutputFormat.wav.isLossless)
    }

    @Test("Audio and video item status values preserve associated output data")
    func conversionStatusesPreserveAssociatedValues() {
        let output = URL(fileURLWithPath: "/tmp/output.m4a")
        let video = VideoConversionItem(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mov"),
            sourceBytes: 42,
            status: .completed(output)
        )
        let audio = AudioConversionItem(
            sourceURL: URL(fileURLWithPath: "/tmp/input.wav"),
            sourceBytes: 42,
            status: .failed("codec")
        )

        #expect(video.sourceBytes == 42)
        #expect(video.status == .completed(output))
        #expect(audio.status == .failed("codec"))
    }

    @Test("Conversion gradient stops clamp user-edited locations")
    func conversionGradientStopClampsLocation() {
        let start = ConversionGradientStop(color: .red, location: -2)
        let end = ConversionGradientStop(color: .blue, location: 4)

        #expect(start.location == 0)
        #expect(end.location == 1)
    }

    @Test("Batch progress reports zero for an empty workload")
    func emptyBatchProgressIsZero() {
        let progress = ImageBatchProgress(
            completed: 0,
            total: 0,
            succeeded: 0,
            failed: 0,
            lastSourceURL: nil
        )

        #expect(progress.fractionCompleted == 0)
    }

    @Test("Empty batch conversion returns no phantom successes or failures")
    func emptyBatchConversionIsNoOp() async {
        let result = await ImageBatchConverter().convert([], maxConcurrentConversions: 0)

        #expect(result.totalRequested == 0)
        #expect(result.successes.isEmpty)
        #expect(result.failures.isEmpty)
        #expect(!result.wasCancelled)
    }

    @Test("Audio requests preserve the explicit video source kind")
    func audioRequestPreservesVideoSourceKind() {
        let request = AudioConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/output"),
            outputFormat: .aac,
            bitRate: .veryHigh,
            sourceKind: .video
        )

        #expect(request.sourceKind == .video)
        #expect(request.bitRate == .veryHigh)
    }

    @Test("Native video input extensions remain intentionally narrow")
    func nativeVideoExtensionsAreStable() {
        #expect(AudioConversionEngine.supportedVideoInputExtensions == ["mov", "mp4", "m4v"])
        #expect(!AudioConversionEngine.supportedVideoInputExtensions.contains("avi"))
    }

    @Test("Persisted conversion statuses and media kinds round-trip")
    func persistedEnumsRoundTrip() throws {
        let statuses = [PersistedConversionStatus.ready, .completed, .failed, .cancelled]
        let kinds = [ConversionMediaKind.image, .video, .audio]

        let statusData = try JSONEncoder().encode(statuses)
        let kindData = try JSONEncoder().encode(kinds)
        let decodedStatuses = try JSONDecoder().decode([PersistedConversionStatus].self, from: statusData)
        let decodedKinds = try JSONDecoder().decode([ConversionMediaKind].self, from: kindData)

        #expect(decodedStatuses == statuses)
        #expect(decodedKinds == kinds)
    }

    @Test("Image conversion rejects quality outside the closed unit interval")
    func invalidQualityIsRejectedBeforeFileAccess() async {
        let request = ImageConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/missing.png"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/cleanfile-output"),
            outputFormat: .png,
            quality: 1.01
        )
        var receivedError: ImageConversionError?

        do {
            _ = try await ImageConversionEngine().convert(request)
        } catch let error as ImageConversionError {
            receivedError = error
        } catch {
            Issue.record("Unexpected conversion error: \(error)")
        }

        #expect(receivedError == .invalidQuality(1.01))
    }

    @Test("Image conversion rejects non-positive resize dimensions")
    func invalidResizeDimensionIsRejectedBeforeFileAccess() async {
        let request = ImageConversionRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/missing.png"),
            destinationDirectory: URL(fileURLWithPath: "/tmp/cleanfile-output"),
            outputFormat: .png,
            resizePolicy: .fit(maxPixelDimension: 0)
        )
        var receivedError: ImageConversionError?

        do {
            _ = try await ImageConversionEngine().convert(request)
        } catch let error as ImageConversionError {
            receivedError = error
        } catch {
            Issue.record("Unexpected conversion error: \(error)")
        }

        #expect(receivedError == .invalidMaximumPixelDimension(0))
    }
}
