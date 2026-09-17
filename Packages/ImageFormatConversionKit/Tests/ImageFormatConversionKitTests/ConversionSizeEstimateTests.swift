import Foundation
import Testing
@testable import ImageFormatConversionKit

@Suite("Conversion size estimates")
struct ConversionSizeEstimateTests {
    @Test("Lossy audio size follows duration and selected bitrate")
    func lossyAudioUsesDurationAndBitrate() throws {
        let item = AudioConversionItem(
            sourceURL: URL(fileURLWithPath: "/tmp/input.wav"),
            sourceBytes: 50_000_000,
            duration: 300
        )

        let estimate = try #require(
            ConversionSizeEstimate.audio(items: [item], format: .mp3, bitRate: .high)
        )

        #expect(estimate.originalBytes == 50_000_000)
        #expect(estimate.likelyBytes == 7_272_000)
        #expect(estimate.lowerBoundBytes <= estimate.likelyBytes)
        #expect(estimate.likelyBytes <= estimate.upperBoundBytes)
    }

    @Test("Lossless PCM estimate is larger than lossy audio for the same duration")
    func pcmIsLargerThanLossyAudio() throws {
        let item = AudioConversionItem(
            sourceURL: URL(fileURLWithPath: "/tmp/input.m4a"),
            sourceBytes: 8_000_000,
            duration: 180
        )

        let lossy = try #require(
            ConversionSizeEstimate.audio(items: [item], format: .aac, bitRate: .standard)
        )
        let pcm = try #require(
            ConversionSizeEstimate.audio(items: [item], format: .wav, bitRate: .standard)
        )

        #expect(pcm.likelyBytes > lossy.likelyBytes)
    }

    @Test("PCM estimate respects source sample rate and channel count")
    func pcmUsesSourceAudioShape() throws {
        let mono = AudioConversionItem(
            sourceURL: URL(fileURLWithPath: "/tmp/mono.wav"),
            sourceBytes: 1_000_000,
            duration: 10,
            sampleRate: 48_000,
            channelCount: 1
        )
        let stereo = AudioConversionItem(
            sourceURL: URL(fileURLWithPath: "/tmp/stereo.wav"),
            sourceBytes: 2_000_000,
            duration: 10,
            sampleRate: 48_000,
            channelCount: 2
        )

        let monoEstimate = try #require(
            ConversionSizeEstimate.audio(items: [mono], format: .wav, bitRate: .standard)
        )
        let stereoEstimate = try #require(
            ConversionSizeEstimate.audio(items: [stereo], format: .wav, bitRate: .standard)
        )

        #expect(stereoEstimate.likelyBytes - 4_096 == (monoEstimate.likelyBytes - 4_096) * 2)
    }

    @Test("Image downscaling reduces the estimated output")
    func imageResizeReducesEstimate() throws {
        let info = imageInfo(width: 6_000, height: 4_000, sourceBytes: 18_000_000)
        let original = try #require(
            ConversionSizeEstimate.image(
                infos: [info],
                format: .jpeg,
                quality: 0.8,
                resize: .original,
                metadata: .removeAll
            )
        )
        let resized = try #require(
            ConversionSizeEstimate.image(
                infos: [info],
                format: .jpeg,
                quality: 0.8,
                resize: .medium,
                metadata: .removeAll
            )
        )

        #expect(resized.likelyBytes < original.likelyBytes)
        #expect(resized.originalBytes == original.originalBytes)
    }

    @Test("Uncompressed bitmap settings may estimate growth")
    func bitmapCanGrowBeyondSource() throws {
        let estimate = try #require(
            ConversionSizeEstimate.image(
                infos: [imageInfo(width: 4_000, height: 3_000, sourceBytes: 2_000_000)],
                format: .bmp,
                quality: 1,
                resize: .original,
                metadata: .preserve
            )
        )

        #expect(estimate.likelyBytes > estimate.originalBytes)
        #expect(estimate.lowerBoundBytes <= estimate.likelyBytes)
        #expect(estimate.likelyBytes <= estimate.upperBoundBytes)
    }

    @Test("Video native estimate is presented as a bounded range")
    func videoEstimateHasStableBounds() {
        let estimate = ConversionSizeEstimate.video(
            originalBytes: 20_000_000,
            estimatedBytes: 8_000_000
        )

        #expect(estimate.originalBytes == 20_000_000)
        #expect(estimate.likelyBytes == 8_000_000)
        #expect(estimate.lowerBoundBytes == 6_800_000)
        #expect(estimate.upperBoundBytes == 9_200_000)
    }

    @Test("ProRes fallback reflects codec data rate and source duration")
    func proResFallbackUsesMediaCharacteristics() throws {
        let proRes422 = try #require(
            ConversionSizeEstimate.proResOutputBytes(
                duration: 10,
                width: 1_920,
                height: 1_080,
                framesPerSecond: 29.97,
                codec: .proRes422
            )
        )
        let proRes4444 = try #require(
            ConversionSizeEstimate.proResOutputBytes(
                duration: 10,
                width: 1_920,
                height: 1_080,
                framesPerSecond: 29.97,
                codec: .proRes4444
            )
        )
        let doubleDuration = try #require(
            ConversionSizeEstimate.proResOutputBytes(
                duration: 20,
                width: 1_920,
                height: 1_080,
                framesPerSecond: 29.97,
                codec: .proRes422
            )
        )

        #expect(proRes4444 > proRes422)
        #expect(doubleDuration == proRes422 * 2)
    }

    @Test("ProRes fallback rejects codecs that retain native estimation")
    func proResFallbackRejectsOtherCodecs() {
        #expect(
            ConversionSizeEstimate.proResOutputBytes(
                duration: 10,
                width: 1_920,
                height: 1_080,
                framesPerSecond: 30,
                codec: .h264
            ) == nil
        )
    }

    private func imageInfo(width: Int, height: Int, sourceBytes: Int64) -> ImageAssetInfo {
        ImageAssetInfo(
            sourceURL: URL(fileURLWithPath: "/tmp/input.jpg"),
            typeIdentifier: "public.jpeg",
            pixelWidth: width,
            pixelHeight: height,
            frameCount: 1,
            fileSizeBytes: sourceBytes,
            hasAlpha: false
        )
    }
}
