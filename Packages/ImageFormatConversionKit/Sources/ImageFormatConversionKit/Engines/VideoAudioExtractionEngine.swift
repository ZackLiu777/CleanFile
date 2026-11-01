//
//  从视频读取音频轨道，并流式写入中间 PCM 文件供音频转换使用。
//  处理受保护内容、缺少音轨、读取和写入失败，以及任务取消。
//  Actor 跟踪活动 reader 和 writer，使调用方能取消正在进行的提取。
//  音频转换引擎在视频输入路径调用它，提取结果随后进入普通音频编码。
//  媒体读取与写入按样本推进，取消和失败会停止活动的媒体处理对象。
//

import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

/// 管理视频音轨提取期间的 reader 和 writer，供上层协调取消。
actor VideoAudioExtractionEngine {
    private var activeReaders: [UUID: AVAssetReader] = [:]
    private var activeWriters: [UUID: AVAssetWriter] = [:]

    /// 验证视频未受保护且包含音轨，并返回非负有限时长。
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

    /// 将音轨分样本写入 CAF PCM；写入不可用时让出执行权。
    /// 失败或取消时停止 reader 和 writer，并向调用方传播错误。
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

    /// 请求停止所有活动提取的 reader 和 writer。
    func cancelAll() {
        activeReaders.values.forEach { $0.cancelReading() }
        activeWriters.values.forEach { $0.cancelWriting() }
    }

    /// 从首条音轨读取采样率，并将输出声道数限制为一至两声道。
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
