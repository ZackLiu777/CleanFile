//
//  ConversionSizeEstimate.swift
//  ImageFormatConversionKit
//

import Foundation

/// A deliberately bounded estimate: variable-rate codecs cannot promise an exact size
/// before encoding, so callers present a range instead of false precision.
struct ConversionSizeEstimate: Equatable, Sendable {
    let originalBytes: Int64
    let likelyBytes: Int64
    let lowerBoundBytes: Int64
    let upperBoundBytes: Int64

    init(originalBytes: Int64, likelyBytes: Int64, lowerBoundBytes: Int64, upperBoundBytes: Int64) {
        self.originalBytes = max(originalBytes, 0)
        self.likelyBytes = max(likelyBytes, 0)
        self.lowerBoundBytes = max(min(lowerBoundBytes, upperBoundBytes), 0)
        self.upperBoundBytes = max(max(lowerBoundBytes, upperBoundBytes), 0)
    }

    static func image(
        infos: [ImageAssetInfo],
        format: ImageOutputFormat,
        quality: Double,
        resize: ImageResizePreset,
        metadata: ImageMetadataPolicy
    ) -> Self? {
        guard !infos.isEmpty else { return nil }
        let original = infos.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
        var likely = 0.0
        var lower = 0.0
        var upper = 0.0

        for info in infos {
            let sourcePixels = pixelCount(width: info.pixelWidth, height: info.pixelHeight)
            let targetPixels = imageTargetPixels(info: info, resize: resize)
            let quality = min(max(quality, 0.1), 1)
            let bitsPerPixel: (likely: Double, lower: Double, upper: Double)
            switch format {
            case .jpeg:
                bitsPerPixel = (0.35 + 2.1 * quality * quality, 0.24 + 1.25 * quality, 0.8 + 3.4 * quality)
            case .heic, .heif:
                bitsPerPixel = (0.25 + 1.35 * quality * quality, 0.18 + 0.8 * quality, 0.55 + 2.2 * quality)
            case .webp:
                bitsPerPixel = (0.28 + 1.55 * quality * quality, 0.2 + 0.9 * quality, 0.65 + 2.5 * quality)
            case .png:
                bitsPerPixel = (4.0, 1.0, 12.0)
            case .tiff:
                bitsPerPixel = (16.0, 8.0, 32.0)
            case .gif:
                bitsPerPixel = (4.0, 1.5, 8.0)
            case .bmp:
                bitsPerPixel = (24.0, 24.0, 32.0)
            }

            let metadataBytes: Double = switch metadata {
            case .preserve: min(Double(info.fileSizeBytes) * 0.04, 512_000)
            case .removeGPS: min(Double(info.fileSizeBytes) * 0.015, 192_000)
            case .removeAll: 0
            }
            let sourcePayloadBytes = max(Double(info.fileSizeBytes) - metadataBytes, 1)
            let sourceBitsPerPixel = sourcePayloadBytes * 8 / sourcePixels
            let expectedSourceBitsPerPixel = expectedImageBitsPerPixel(
                typeIdentifier: info.typeIdentifier
            )
            // Source bytes capture whether the image is simple artwork, a screenshot,
            // or a detailed photo. A bounded factor carries that signal into the output codec.
            let contentComplexity = min(max(sourceBitsPerPixel / expectedSourceBitsPerPixel, 0.4), 2.5)
            likely += targetPixels * bitsPerPixel.likely * contentComplexity / 8 + metadataBytes
            lower += targetPixels * bitsPerPixel.lower * contentComplexity / 8
            upper += targetPixels * bitsPerPixel.upper * contentComplexity / 8 + metadataBytes

            // Very small images are dominated by headers and container metadata.
            if sourcePixels < 65_536 {
                likely += 2_048
                lower += 1_024
                upper += 8_192
            }
        }
        return Self(
            originalBytes: original,
            likelyBytes: Int64(likely.rounded()),
            lowerBoundBytes: Int64(lower.rounded()),
            upperBoundBytes: Int64(upper.rounded())
        )
    }

    static func audio(
        items: [AudioConversionItem],
        format: AudioOutputFormat,
        bitRate: AudioBitRate
    ) -> Self? {
        let measurable = items.compactMap { item -> AudioConversionItem? in
            guard let duration = item.duration, duration > 0 else { return nil }
            return item
        }
        guard !measurable.isEmpty else { return nil }

        let original = measurable.reduce(Int64(0)) { $0 + $1.sourceBytes }
        var likely = 0.0
        var lower = 0.0
        var upper = 0.0
        for item in measurable {
            let duration = item.duration ?? 0
            let sampleRate = max(item.sampleRate ?? 44_100, 8_000)
            let channels = Double(min(max(item.channelCount ?? 2, 1), 2))
            switch format {
            case .mp3, .aac, .aacFile:
                let payload = duration * Double(bitRate.rawValue) / 8
                likely += payload * 1.01
                lower += payload * 0.995
                upper += payload * 1.035
            case .wav, .aiff, .cafPCM:
                let pcm = duration * sampleRate * channels * 2
                likely += pcm + 4_096
                lower += pcm
                upper += pcm + 16_384
            case .alac, .cafALAC:
                let pcm = duration * sampleRate * channels * 2
                likely += pcm * 0.56
                lower += pcm * 0.42
                upper += pcm * 0.72
            }
        }

        return Self(
            originalBytes: original,
            likelyBytes: Int64(likely.rounded()),
            lowerBoundBytes: Int64(lower.rounded()),
            upperBoundBytes: Int64(upper.rounded())
        )
    }

    static func video(originalBytes: Int64, estimatedBytes: Int64) -> Self {
        Self(
            originalBytes: originalBytes,
            likelyBytes: estimatedBytes,
            lowerBoundBytes: Int64(Double(estimatedBytes) * 0.85),
            upperBoundBytes: Int64(Double(estimatedBytes) * 1.15)
        )
    }

    /// ProRes export presets do not consistently expose an AVFoundation size estimate.
    /// Scale Apple's nominal 1080p/29.97 fps data rates by encoded macroblock rate and add LPCM audio.
    static func proResOutputBytes(
        duration: TimeInterval,
        width: Int,
        height: Int,
        framesPerSecond: Double,
        codec: VideoCodec
    ) -> Int64? {
        guard duration > 0,
              width > 0,
              height > 0,
              codec == .proRes422 || codec == .proRes4444 else {
            return nil
        }

        // ProRes operates on 16×16 macroblocks. Rounding dimensions before scaling is
        // measurably more accurate for non-standard and portrait video dimensions.
        let macroblocksWide = ceil(Double(width) / 16)
        let macroblocksHigh = ceil(Double(height) / 16)
        let referenceMacroblocks = ceil(1_920.0 / 16) * ceil(1_080.0 / 16)
        let macroblockScale = (macroblocksWide * macroblocksHigh) / referenceMacroblocks
        let frameRateScale = min(max(framesPerSecond, 1), 120) / 29.97
        let videoBitsPerSecond = switch codec {
        case .proRes422: 147_000_000.0
        case .proRes4444: 330_000_000.0
        case .h264, .hevc: 0.0
        }
        // These AVFoundation presets produce 48 kHz stereo 16-bit LPCM audio.
        let audioBitsPerSecond = 48_000.0 * 2 * 16
        let payloadBytes = duration
            * (videoBitsPerSecond * macroblockScale * frameRateScale + audioBitsPerSecond)
            / 8

        // MOV sample tables are small relative to ProRes payloads.
        return Int64((payloadBytes * 1.005).rounded())
    }

    private static func imageTargetPixels(info: ImageAssetInfo, resize: ImageResizePreset) -> Double {
        if resize == .square1024 { return 1_024 * 1_024 }
        guard resize != .original else {
            return pixelCount(width: info.pixelWidth, height: info.pixelHeight)
        }
        let longest = max(info.pixelWidth, info.pixelHeight)
        guard longest > resize.rawValue else {
            return pixelCount(width: info.pixelWidth, height: info.pixelHeight)
        }
        let scale = Double(resize.rawValue) / Double(longest)
        return pixelCount(width: info.pixelWidth, height: info.pixelHeight) * scale * scale
    }

    private static func pixelCount(width: Int, height: Int) -> Double {
        // Convert each dimension before multiplying so untrusted metadata cannot overflow Int.
        Double(max(width, 1)) * Double(max(height, 1))
    }

    private static func expectedImageBitsPerPixel(typeIdentifier: String?) -> Double {
        let identifier = typeIdentifier?.lowercased() ?? ""
        if identifier.contains("jpeg") { return 1.5 }
        if identifier.contains("heic") || identifier.contains("heif") { return 0.9 }
        if identifier.contains("webp") { return 1.2 }
        if identifier.contains("png") { return 4.0 }
        if identifier.contains("tiff") { return 16.0 }
        if identifier.contains("gif") { return 4.0 }
        if identifier.contains("bmp") { return 24.0 }
        return 2.0
    }
}
