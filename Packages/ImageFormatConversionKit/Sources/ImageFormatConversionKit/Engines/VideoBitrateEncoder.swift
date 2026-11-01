//
//  自定义码率视频编码，将视频、音频和可选元数据轨道分别流式传递。
//  码率及尺寸由源视频和请求计算；HDR 在此 SDR 路径中明确拒绝。
//  锁保护活动 reader / writer 的取消入口，任一轨道失败时停止整个编码。
//  视频转换引擎仅在请求自定义码率的路径中使用此编码器。
//  媒体样本通过系统 reader 和 writer 处理；输出路径及最终提交由上层协调。
//

import AVFoundation
import Foundation

/// 按源视频码率的指定比例编码；自动码率仍由系统预设导出器处理。
final class VideoBitrateEncoder: @unchecked Sendable {
    private let lock = NSLock()
    private var reader: AVAssetReader?
    private var writer: AVAssetWriter?

    /// 通过锁访问活动读写器，可从任务取消处理器安全地请求停止。
    func cancel() {
        lock.withLock {
            reader?.cancelReading()
            writer?.cancelWriting()
        }
    }

    /// 创建视频及可选音频、元数据管线，并等待所有管线结束后完成写入。
    /// 自定义 SDR 编码拒绝 HDR，任一管线失败时取消所有读写。
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

    /// 将目标容器转换为 AVFoundation 文件类型。
    private static func fileType(_ container: VideoOutputContainer) -> AVFileType {
        switch container {
        case .mp4: .mp4
        case .mov: .mov
        case .m4v: .m4v
        }
    }
}

/// 为自定义码率路径计算偶数像素尺寸和目标视频码率。
enum VideoBitratePlan {
    /// 按最长边等比缩小，不放大源视频，并将两个维度调整为偶数。
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

    /// 按码率比例和像素面积比例计算目标值，并设置最低码率。
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

    /// 绑定一组轨道读写端以及负责整体状态的 reader 和 writer。
    init(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput, reader: AVAssetReader, writer: AVAssetWriter) {
        self.output = output
        self.input = input
        self.reader = reader
        self.writer = writer
    }

    /// 持续传递样本并检查取消；视频管线按时间戳报告进度。
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
