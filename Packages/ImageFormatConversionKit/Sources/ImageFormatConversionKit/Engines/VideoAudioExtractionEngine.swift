//
//  文件职责：实现 VideoAudioExtraction 底层处理流程，并向上层提供稳定入口。
//  所属模块：ImageFormatConversionKit。
//

import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

/// 使用 Actor 隔离 `VideoAudioExtractionEngine` 的可变状态，确保并发访问安全。
actor VideoAudioExtractionEngine {
    private var activeReaders: [UUID: AVAssetReader] = [:]
    private var activeWriters: [UUID: AVAssetWriter] = [:]

    /// 执行 `inspect` 分析流程，在遵守文件访问边界的前提下生成结果。
    func inspect(_ sourceURL: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: sourceURL)
        if try await asset.load(.hasProtectedContent) {
            throw AudioConversionError.protectedVideo
        }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw AudioConversionError.videoHasNoAudio }
        let duration = try await asset.load(.duration)
        return duration.seconds.isFinite ? max(duration.seconds, 0) : 0
    }

    /// 封装 `extractPCM` 对应的局部行为，供当前类型在统一入口下复用。
    func extractPCM(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        if try await asset.load(.hasProtectedContent) {
            throw AudioConversionError.protectedVideo
        }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw AudioConversionError.videoHasNoAudio }
        let duration = try await asset.load(.duration)
        let durationSeconds = max(duration.seconds, 0)
        let streamSettings = try await pcmStreamSettings(for: tracks[0])

        let reader = try AVAssetReader(asset: asset)
        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: streamSettings.sampleRate,
            AVNumberOfChannelsKey: streamSettings.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderAudioMixOutput(
            audioTracks: tracks,
            audioSettings: pcmSettings
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw AudioConversionError.invalidAudio }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .caf)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: pcmSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw AudioConversionError.invalidAudio }
        writer.add(writerInput)

        let operationID = UUID()
        activeReaders[operationID] = reader
        activeWriters[operationID] = writer
        defer {
            activeReaders[operationID] = nil
            activeWriters[operationID] = nil
        }

        guard writer.startWriting(), reader.startReading() else {
            throw AudioConversionError.conversionFailed(
                reader.error?.localizedDescription
                    ?? writer.error?.localizedDescription
                    ?? L10n.string("audio.error.invalid")
            )
        }
        writer.startSession(atSourceTime: .zero)
        await progress(0)

        do {
            while reader.status == .reading {
                try Task.checkCancellation()
                guard writerInput.isReadyForMoreMediaData else {
                    await Task.yield()
                    continue
                }
                guard let sample = readerOutput.copyNextSampleBuffer() else { break }
                guard writerInput.append(sample) else {
                    throw AudioConversionError.conversionFailed(
                        writer.error?.localizedDescription ?? L10n.string("audio.error.invalid")
                    )
                }
                if durationSeconds > 0 {
                    let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    if seconds.isFinite {
                        await progress(min(max(seconds / durationSeconds, 0), 1))
                    }
                }
            }
            if reader.status == .failed {
                throw AudioConversionError.conversionFailed(
                    reader.error?.localizedDescription ?? L10n.string("audio.error.invalid")
                )
            }
            try Task.checkCancellation()
            writerInput.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw AudioConversionError.conversionFailed(
                    writer.error?.localizedDescription ?? L10n.string("audio.error.invalid")
                )
            }
            await progress(1)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            if error is CancellationError { throw AudioConversionError.cancelled }
            throw error
        }
    }

    /// 取消 `cancelAll` 对应的进行中任务，并收敛到可继续操作的状态。
    func cancelAll() {
        activeReaders.values.forEach { $0.cancelReading() }
        activeWriters.values.forEach { $0.cancelWriting() }
    }

    /// 封装 `pcmStreamSettings` 对应的局部行为，供当前类型在统一入口下复用。
    private func pcmStreamSettings(for track: AVAssetTrack) async throws -> (
        sampleRate: Double,
        channelCount: Int
    ) {
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else { throw AudioConversionError.invalidAudio }
        let stream = basicDescription.pointee
        guard stream.mSampleRate > 0, stream.mChannelsPerFrame > 0 else {
            throw AudioConversionError.invalidAudio
        }
        return (stream.mSampleRate, Int(min(max(stream.mChannelsPerFrame, 1), 2)))
    }
}
