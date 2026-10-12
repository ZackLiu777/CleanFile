import AVFoundation
import Foundation

/// Encodes a video at a target fraction of its source track's measured bit rate.
/// The preset exporter remains responsible for the automatic (100%) setting.
final class VideoBitrateEncoder: @unchecked Sendable {
    private let lock = NSLock()
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?

    func cancel() {
        lock.withLock {
            reader?.cancelReading()
            writer?.cancelWriting()
        }
    }

    func encode(
        asset: AVURLAsset,
        request: VideoConversionRequest,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        guard let fraction = request.bitRateFraction,
              fraction >= 0.1, fraction < 1,
              request.codec == .h264 || request.codec == .hevc,
              let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoConversionError.unsupportedSettings
        }

        let sourceRate = Double(try await videoTrack.load(.estimatedDataRate))
        guard sourceRate > 0 else { throw VideoConversionError.unsupportedSettings }
        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let sourceWidth = abs(size.width)
        let sourceHeight = abs(size.height)
        guard sourceWidth > 0, sourceHeight > 0 else { throw VideoConversionError.unsupportedSettings }
        // The BGRA encoder path is SDR. Refuse HDR instead of silently washing out
        // Dolby Vision / HLG highlights; the automatic system exporter supports them.
        for format in try await videoTrack.load(.formatDescriptions) {
            let transfer = CMFormatDescriptionGetExtension(
                format,
                extensionKey: kCMFormatDescriptionExtension_TransferFunction
            ) as? String
            if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
                || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
                throw VideoConversionError.hdrBitrateUnsupported
            }
        }
        let dimensions = VideoBitratePlan.dimensions(source: size, resolution: request.resolution)
        let width = dimensions.width
        let height = dimensions.height
        let rate = VideoBitratePlan.rate(sourceRate: sourceRate, fraction: fraction, source: size, output: dimensions)

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw VideoConversionError.unsupportedSettings }
        reader.add(videoOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: Self.fileType(request.container))
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: request.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: rate]
        ])
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else { throw VideoConversionError.unsupportedSettings }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM
            ])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else {
                throw VideoConversionError.unsupportedSettings
            }
            reader.add(output)
            writer.add(input)
            audioOutput = output
            audioInput = input
        }

        // Live Photo pairing depends on both the movie metadata and its timed track.
        var metadataPipes: [SamplePipe] = []
        if request.preservesTimedMetadata {
            guard request.container == .mov else { throw VideoConversionError.unsupportedSettings }
            writer.metadata = try await asset.load(.metadata)
            for track in try await asset.loadTracks(withMediaType: .metadata) {
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                let formats = try await track.load(.formatDescriptions)
                let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: formats.first)
                guard reader.canAdd(output), writer.canAdd(input) else { throw VideoConversionError.unsupportedSettings }
                reader.add(output)
                writer.add(input)
                metadataPipes.append(SamplePipe(output: output, input: input, reader: reader, writer: writer))
            }
        }

        try Task.checkCancellation()
        lock.withLock {
            self.reader = reader
            self.writer = writer
        }
        defer {
            lock.withLock {
                self.reader = nil
                self.writer = nil
            }
        }

        guard writer.startWriting(), reader.startReading() else {
            cancel()
            throw VideoConversionError.exportFailed((writer.error ?? reader.error)?.localizedDescription ?? "Unable to start encoding")
        }
        writer.startSession(atSourceTime: .zero)
        let duration = (try await asset.load(.duration)).seconds
        let videoPipe = SamplePipe(output: videoOutput, input: videoInput, reader: reader, writer: writer)
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await videoPipe.append(duration: duration, progress: progress) }
                if let audioOutput, let audioInput {
                    let pipe = SamplePipe(output: audioOutput, input: audioInput, reader: reader, writer: writer)
                    group.addTask { try await pipe.append(duration: duration, progress: nil) }
                }
                for pipe in metadataPipes {
                    group.addTask { try await pipe.append(duration: duration, progress: nil) }
                }
                // Fail promptly so a blocked sibling pipe is cancelled as well.
                while let _ = try await group.next() { }
            }
            guard reader.status == .completed else {
                throw reader.error ?? VideoConversionError.exportFailed("Unable to read source media")
            }
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error ?? VideoConversionError.exportFailed("Unable to finish encoding")
            }
        } catch {
            cancel()
            throw error
        }
    }

    private static func fileType(_ container: VideoOutputContainer) -> AVFileType {
        switch container {
        case .mp4: .mp4
        case .mov: .mov
        case .m4v: .m4v
        }
    }
}

enum VideoBitratePlan {
    static func dimensions(source: CGSize, resolution: VideoResolutionPreset) -> (width: Int, height: Int) {
        let longestEdge: CGFloat = switch resolution {
        case .original: max(abs(source.width), abs(source.height))
        case .ultraHD: 3840
        case .fullHD: 1920
        case .hd: 1280
        case .sd: 640
        }
        let scale = min(1, longestEdge / max(abs(source.width), abs(source.height)))
        return (
            max(2, Int((abs(source.width) * scale / 2).rounded()) * 2),
            max(2, Int((abs(source.height) * scale / 2).rounded()) * 2)
        )
    }

    static func rate(
        sourceRate: Double,
        fraction: Double,
        source: CGSize,
        output: (width: Int, height: Int)
    ) -> Int {
        let ratio = Double(output.width * output.height) / Double(abs(source.width * source.height))
        return Int(max(250_000, sourceRate * fraction * ratio))
    }
}

// Each pipe has one producer task; audio and video touch separate reader outputs
// and writer inputs while the owning encoder waits for both before finishing.
private final class SamplePipe: @unchecked Sendable {
    let output: AVAssetReaderTrackOutput
    let input: AVAssetWriterInput
    let reader: AVAssetReader
    let writer: AVAssetWriter

    init(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput, reader: AVAssetReader, writer: AVAssetWriter) {
        self.output = output
        self.input = input
        self.reader = reader
        self.writer = writer
    }

    func append(duration: Double, progress: (@Sendable (Double) async -> Void)?) async throws {
        while true {
            try Task.checkCancellation()
            guard reader.status == .reading || reader.status == .completed, writer.status == .writing else {
                throw VideoConversionError.cancelled
            }
            guard input.isReadyForMoreMediaData else {
                try await Task.sleep(for: .milliseconds(5))
                continue
            }
            guard let sample = output.copyNextSampleBuffer() else { break }
            guard input.append(sample) else {
                throw VideoConversionError.exportFailed("Unable to append media sample")
            }
            if let progress, duration.isFinite, duration > 0 {
                await progress(min(0.99, max(0, sample.presentationTimeStamp.seconds / duration)))
            }
        }
        input.markAsFinished()
    }
}
