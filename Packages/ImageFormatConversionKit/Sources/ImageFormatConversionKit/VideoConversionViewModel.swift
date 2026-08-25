import Foundation
import Observation

@MainActor
@Observable
public final class VideoConversionViewModel {
    public private(set) var items: [VideoConversionItem] = []
    public private(set) var isConverting = false
    public private(set) var completed = 0
    public private(set) var total = 0
    public private(set) var currentProgress = 0.0
    public private(set) var notice: String?

    public var container: VideoOutputContainer = .mp4
    public var codec: VideoCodec = .h264
    public var resolution: VideoResolutionPreset = .original
    public let outputDirectory: URL

    private let engine: VideoConversionEngine
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        outputDirectory: URL? = nil,
        engine: VideoConversionEngine = VideoConversionEngine()
    ) {
        self.outputDirectory = outputDirectory ?? Self.defaultOutputDirectory()
        self.engine = engine
    }

    public var canConvert: Bool {
        !isConverting && items.contains { item in
            switch item.status {
            case .ready, .failed, .cancelled: true
            case .converting, .completed: false
            }
        }
    }

    public var availableResolutions: [VideoResolutionPreset] {
        switch codec {
        case .hevc: [.original, .ultraHD, .fullHD]
        case .proRes422, .proRes4444: [.original]
        case .h264: VideoResolutionPreset.allCases
        }
    }

    public var availableContainers: [VideoOutputContainer] {
        switch codec {
        case .proRes422, .proRes4444: [.mov]
        case .hevc: [.mp4, .mov]
        case .h264: VideoOutputContainer.allCases
        }
    }

    public func addFiles(_ urls: [URL]) {
        guard !isConverting else { return }
        let allowedExtensions = Set(["mov", "mp4", "m4v"])
        let supportedURLs = urls.filter {
            allowedExtensions.contains($0.pathExtension.lowercased())
        }
        if supportedURLs.count != urls.count {
            notice = L10n.string("video.error.unsupported_import")
        }
        var known = Set(items.map { $0.sourceURL.standardizedFileURL })
        for url in supportedURLs where known.insert(url.standardizedFileURL).inserted {
            let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            items.append(VideoConversionItem(sourceURL: url, sourceBytes: bytes))
        }
    }

    public func remove(_ id: UUID) {
        guard !isConverting else { return }
        items.removeAll { $0.id == id }
    }

    public func removeAll() {
        guard !isConverting else { return }
        items.removeAll()
        notice = nil
    }

    public func reportImportFailure(_ message: String) {
        notice = L10n.format("notice.import_failed", message)
    }

    public func start() {
        guard canConvert else { return }
        task?.cancel()
        task = Task { [weak self] in await self?.run() }
    }

    public func cancel() {
        task?.cancel()
        Task { await engine.cancelAll() }
    }

    private func run() async {
        isConverting = true
        notice = nil
        completed = 0
        let candidateIDs = Set(items.compactMap { item -> UUID? in
            switch item.status {
            case .ready, .failed, .cancelled: item.id
            case .converting, .completed: nil
            }
        })
        total = candidateIDs.count

        for index in items.indices where candidateIDs.contains(items[index].id) {
            if Task.isCancelled {
                items[index].status = .cancelled
                continue
            }
            items[index].status = .converting
            currentProgress = 0
            let request = VideoConversionRequest(
                sourceURL: items[index].sourceURL,
                destinationDirectory: outputDirectory,
                container: container,
                codec: codec,
                resolution: resolution
            )
            do {
                let result = try await engine.convert(request) { [weak self] value in
                    await MainActor.run { self?.currentProgress = value }
                }
                items[index].status = .completed(result.outputURL)
            } catch let error as VideoConversionError {
                items[index].status = error == .cancelled
                    ? .cancelled
                    : .failed(error.localizedDescription)
            } catch is CancellationError {
                items[index].status = .cancelled
            } catch {
                items[index].status = .failed(error.localizedDescription)
            }
            completed += 1
        }

        let successes = items.reduce(into: 0) { count, item in
            if case .completed = item.status { count += 1 }
        }
        notice = Task.isCancelled
            ? L10n.string("notice.cancelled")
            : L10n.format("video.notice.completed", successes)
        isConverting = false
        task = nil
    }

    private static func defaultOutputDirectory() -> URL {
        let manager = FileManager.default
        let base = manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        return base.appendingPathComponent("Converted Videos", isDirectory: true)
    }
}
