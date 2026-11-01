//
//  视频转换使用系统导出器或自定义码率编码器处理不同请求。
//  输出先写入临时文件，完成并检查取消后再移动到目标路径。
//  Actor 跟踪活动导出器以支持取消，并提供与转换配置相匹配的体积估算。
//  视频状态对象通过此入口发起转换、读取进度和估算输出大小。
//  系统导出与自定义编码采用各自的取消入口，错误需要由调用方呈现。
//

import AVFoundation
import Foundation

/// 协调系统导出与自定义码率编码，并跟踪可取消的活动操作。
public actor VideoConversionEngine {
    private var activeExporters: [UUID: AVAssetExportSession] = [:]
    private var activeBitrateEncoders: [UUID: VideoBitrateEncoder] = [:]

    /// 创建视频转换引擎；初始化时不访问输入文件。
    public init() {}

    /// 检查容器和编码设置后导出到临时文件，成功时移动到唯一目标路径。
    /// 取消会转发给当前导出器，失败或取消时清理临时文件。
    public func convert(
        _ request: VideoConversionRequest,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> VideoConversionResult {
        let performanceID = ConversionPerformance.begin("Conversion Video Total")
        defer { ConversionPerformance.end("Conversion Video Total", id: performanceID) }
        if request.codec == .hevc,
           request.resolution == .hd || request.resolution == .sd {
            throw VideoConversionError.unsupportedSettings
        }
        if request.codec == .proRes422 || request.codec == .proRes4444 {
            guard request.container == .mov, request.resolution == .original else {
                throw VideoConversionError.unsupportedSettings
            }
        }
        if request.container == .m4v, request.codec != .h264 {
            throw VideoConversionError.unsupportedSettings
        }
        let fileManager = FileManager.default
        let source = request.sourceURL.standardizedFileURL
        let directory = request.destinationDirectory.standardizedFileURL
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let directoryAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if directoryAccess { directory.stopAccessingSecurityScopedResource() }
        }

        guard (try? source.checkResourceIsReachable()) == true else {
            throw VideoConversionError.sourceNotReachable
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let asset = AVURLAsset(url: source)
        let operationID = UUID()
        let temporaryURL = directory
            .appendingPathComponent(".video-conversion-\(operationID.uuidString)")
            .appendingPathExtension(request.container.fileExtension)
        let outputURL = uniqueDestination(
            source: source,
            directory: directory,
            extension: request.container.fileExtension
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        await progress(0)
        let exportID = ConversionPerformance.begin("Conversion Video Export")
        do {
            if request.bitRateFraction != nil {
                let encoder = VideoBitrateEncoder()
                activeBitrateEncoders[operationID] = encoder
                defer { activeBitrateEncoders[operationID] = nil }
                try await withTaskCancellationHandler {
                    try await encoder.encode(asset: asset, request: request, to: temporaryURL, progress: progress)
                } onCancel: {
                    encoder.cancel()
                }
            } else {
                let preset = exportPreset(codec: request.codec, resolution: request.resolution)
                guard await AVAssetExportSession.compatibility(
                    ofExportPreset: preset,
                    with: asset,
                    outputFileType: fileType(request.container)
                ) else {
                    throw VideoConversionError.unsupportedSettings
                }
                guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
                    throw VideoConversionError.cannotCreateExporter
                }
                if request.preservesTimedMetadata { exporter.metadata = try await asset.load(.metadata) }
                let exporterCancellation = ExporterCancellation(exporter)
                activeExporters[operationID] = exporter
                defer { activeExporters[operationID] = nil }
                let progressTask = Task { await exporterCancellation.observeProgress(progress) }
                defer { progressTask.cancel() }
                try await withTaskCancellationHandler {
                    try await exporter.export(to: temporaryURL, as: fileType(request.container))
                } onCancel: {
                    exporterCancellation.cancel()
                }
            }
        } catch is CancellationError {
            ConversionPerformance.end("Conversion Video Export", id: exportID)
            throw VideoConversionError.cancelled
        } catch VideoConversionError.hdrBitrateUnsupported {
            ConversionPerformance.end("Conversion Video Export", id: exportID)
            throw VideoConversionError.hdrBitrateUnsupported
        } catch {
            ConversionPerformance.end("Conversion Video Export", id: exportID)
            if Task.isCancelled { throw VideoConversionError.cancelled }
            throw VideoConversionError.exportFailed(error.localizedDescription)
        }
        ConversionPerformance.end("Conversion Video Export", id: exportID)

        try Task.checkCancellation()
        let commitID = ConversionPerformance.begin("Conversion Output Commit")
        defer { ConversionPerformance.end("Conversion Output Commit", id: commitID) }
        do {
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            throw VideoConversionError.commitFailed(error.localizedDescription)
        }
        await progress(1)

        let sourceBytes = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let outputBytes = Int64((try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return VideoConversionResult(
            sourceURL: source,
            outputURL: outputURL,
            sourceBytes: sourceBytes,
            outputBytes: outputBytes
        )
    }

    /// 请求取消当前引擎中所有活动的导出器和码率编码器。
    public func cancelAll() {
        activeExporters.values.forEach { $0.cancelExport() }
        activeBitrateEncoders.values.forEach { $0.cancel() }
    }

    /// 使用与转换一致的预设估算输出大小；自定义码率按时长和轨道码率估计。
    /// 系统无法估算 ProRes 时使用尺寸和帧率的后备估算。
    public func estimateOutputBytes(_ request: VideoConversionRequest) async throws -> Int64 {
        let asset = AVURLAsset(url: request.sourceURL.standardizedFileURL)
        if let fraction = request.bitRateFraction {
            guard fraction >= 0.1, fraction < 1,
                  let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw VideoConversionError.unsupportedSettings
            }
            let rate = Double(try await track.load(.estimatedDataRate))
            let size = try await track.load(.naturalSize)
            let duration = (try await asset.load(.duration)).seconds
            guard rate > 0, size.width > 0, size.height > 0, duration.isFinite, duration > 0 else {
                throw VideoConversionError.unsupportedSettings
            }
            let output = VideoBitratePlan.dimensions(source: size, resolution: request.resolution)
            let videoRate = VideoBitratePlan.rate(
                sourceRate: rate,
                fraction: fraction,
                source: size,
                output: output
            )
            let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
            let audioRate = hasAudio ? 192_000.0 : 0
            return Int64((Double(videoRate) + audioRate) * duration / 8 * 1.03)
        }
        let preset = exportPreset(codec: request.codec, resolution: request.resolution)
        guard await AVAssetExportSession.compatibility(
            ofExportPreset: preset,
            with: asset,
            outputFileType: fileType(request.container)
        ), let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw VideoConversionError.unsupportedSettings
        }
        exporter.outputFileType = fileType(request.container)
        let duration = try await asset.load(.duration)
        if duration.isNumeric, duration > .zero {
            // A finite range gives AVFoundation all information needed for its most
            // accurate content-aware estimate instead of relying on an open-ended range.
            exporter.timeRange = CMTimeRange(start: .zero, duration: duration)
        }
        if let bytes = try? await exporter.estimatedOutputFileLengthInBytes, bytes > 0 {
            return bytes
        }
        if let bytes = try await proResFallbackOutputBytes(asset: asset, codec: request.codec) {
            return bytes
        }
        throw VideoConversionError.cannotCreateExporter
    }

    /// 使用变换后的尺寸、时长和帧率估算 ProRes，非 ProRes 返回 nil。
    private func proResFallbackOutputBytes(asset: AVAsset, codec: VideoCodec) async throws -> Int64? {
        guard codec == .proRes422 || codec == .proRes4444 else { return nil }
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(transform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())
        let nominalFrameRate = Double(try await track.load(.nominalFrameRate))

        return ConversionSizeEstimate.proResOutputBytes(
            duration: duration,
            width: width,
            height: height,
            framesPerSecond: nominalFrameRate > 0 ? nominalFrameRate : 30,
            codec: codec
        )
    }

    /// 将编码器与分辨率组合映射到 AVFoundation 导出预设。
    private func exportPreset(codec: VideoCodec, resolution: VideoResolutionPreset) -> String {
        if codec == .proRes422 { return AVAssetExportPresetAppleProRes422LPCM }
        if codec == .proRes4444 { return AVAssetExportPresetAppleProRes4444LPCM }
        if codec == .hevc {
            switch resolution {
            case .ultraHD: return AVAssetExportPresetHEVC3840x2160
            case .fullHD: return AVAssetExportPresetHEVC1920x1080
            case .hd, .sd: return AVAssetExportPresetHEVC1920x1080
            case .original: return AVAssetExportPresetHEVCHighestQuality
            }
        }
        switch resolution {
        case .ultraHD: return AVAssetExportPreset3840x2160
        case .fullHD: return AVAssetExportPreset1920x1080
        case .hd: return AVAssetExportPreset1280x720
        case .sd: return AVAssetExportPreset640x480
        case .original: return AVAssetExportPresetHighestQuality
        }
    }

    /// 将公开容器选项映射为 AVFoundation 文件类型。
    private func fileType(_ container: VideoOutputContainer) -> AVFileType {
        switch container {
        case .mp4: .mp4
        case .mov: .mov
        case .m4v: .m4v
        }
    }

    /// 在目标目录寻找未占用名称，避免有意覆盖现有文件。
    private func uniqueDestination(source: URL, directory: URL, extension ext: String) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        for suffix in 0 ... 9_999 {
            let name = suffix == 0 ? base : "\(base)-\(suffix)"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
}

// AVAssetExportSession predates Swift concurrency. This wrapper is only used
// to forward the thread-safe cancellation method from a cancellation handler.
/// 桥接导出器的取消与进度观察；取消处理器可从其他执行上下文调用。
private final class ExporterCancellation: @unchecked Sendable {
    private let exporter: AVAssetExportSession

    /// 保存当前导出会话，以便转发取消并观察进度。
    init(_ exporter: AVAssetExportSession) {
        self.exporter = exporter
    }

    /// 将取消请求转发给 AVAssetExportSession。
    func cancel() {
        exporter.cancelExport()
    }

    /// 在支持的系统上观察导出状态，旧系统定期读取进度直到任务取消。
    func observeProgress(
        _ report: @escaping @Sendable (Double) async -> Void
    ) async {
        if #available(iOS 18.0, macOS 15.0, *) {
            for await state in exporter.states(updateInterval: 0.1) {
                guard !Task.isCancelled else { return }
                if case let .exporting(progress) = state {
                    await report(progress.fractionCompleted)
                }
            }
        } else {
            while !Task.isCancelled {
                await report(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
