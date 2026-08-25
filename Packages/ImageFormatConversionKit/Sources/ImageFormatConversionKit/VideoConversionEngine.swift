import AVFoundation
import Foundation

public actor VideoConversionEngine {
    private var activeExporters: [UUID: AVAssetExportSession] = [:]

    public init() {}

    public func convert(
        _ request: VideoConversionRequest,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> VideoConversionResult {
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
        let exporterCancellation = ExporterCancellation(exporter)

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

        activeExporters[operationID] = exporter
        defer { activeExporters[operationID] = nil }

        await progress(0)

        do {
            try await withTaskCancellationHandler {
                try await exporter.export(to: temporaryURL, as: fileType(request.container))
            } onCancel: {
                exporterCancellation.cancel()
            }
        } catch is CancellationError {
            throw VideoConversionError.cancelled
        } catch {
            if Task.isCancelled { throw VideoConversionError.cancelled }
            throw VideoConversionError.exportFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
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

    public func cancelAll() {
        activeExporters.values.forEach { $0.cancelExport() }
    }

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

    private func fileType(_ container: VideoOutputContainer) -> AVFileType {
        switch container {
        case .mp4: .mp4
        case .mov: .mov
        case .m4v: .m4v
        }
    }

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
private final class ExporterCancellation: @unchecked Sendable {
    private let exporter: AVAssetExportSession

    init(_ exporter: AVAssetExportSession) {
        self.exporter = exporter
    }

    func cancel() {
        exporter.cancelExport()
    }
}
