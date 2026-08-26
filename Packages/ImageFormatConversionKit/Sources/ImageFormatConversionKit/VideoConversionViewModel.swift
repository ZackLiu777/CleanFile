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
    private(set) var importProgress: ConversionImportProgress?

    public var container: VideoOutputContainer = .mp4
    public var codec: VideoCodec = .h264
    public var resolution: VideoResolutionPreset = .original
    public let outputDirectory: URL

    private let engine: VideoConversionEngine
    private let workspace = ConversionWorkspace.shared
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        outputDirectory: URL? = nil,
        engine: VideoConversionEngine = VideoConversionEngine()
    ) {
        self.outputDirectory = outputDirectory ?? Self.defaultOutputDirectory()
        self.engine = engine
        Task { [weak self] in await self?.restore() }
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

    public func addFiles(
        _ urls: [URL],
        progressRange: ClosedRange<Double> = 0 ... 1
    ) async {
        guard !isConverting, importProgress == nil else { return }
        let allowedExtensions = Set(["mov", "mp4", "m4v"])
        let supportedURLs = urls.filter {
            allowedExtensions.contains($0.pathExtension.lowercased())
        }
        if supportedURLs.count != urls.count {
            notice = L10n.string("video.error.unsupported_import")
        }
        var knownURLs = Set(items.map { $0.sourceURL.standardizedFileURL })
        let uniqueURLs = supportedURLs.filter {
            knownURLs.insert($0.standardizedFileURL).inserted
        }
        guard !uniqueURLs.isEmpty else { return }
        importProgress = ConversionImportProgress(
            completed: 0,
            total: uniqueURLs.count,
            currentFileName: uniqueURLs.first?.lastPathComponent
        ).mapped(to: progressRange)
        defer { importProgress = nil }
        for (index, url) in uniqueURLs.enumerated() {
            importProgress = ConversionImportProgress(
                completed: index,
                total: uniqueURLs.count,
                currentFileName: url.lastPathComponent
            ).mapped(to: progressRange)
            let id = UUID()
            do {
                let (stagedURL, bytes) = try await workspace.stage(
                    url,
                    id: id,
                    kind: .video
                ) { [weak self] copiedBytes, totalBytes in
                    guard totalBytes > 0 else { return }
                    await MainActor.run {
                        self?.importProgress = ConversionImportProgress(
                            completed: index,
                            total: uniqueURLs.count,
                            currentFileName: url.lastPathComponent,
                            currentFileFraction: Double(copiedBytes) / Double(totalBytes)
                        ).mapped(to: progressRange)
                    }
                }
                items.append(VideoConversionItem(id: id, sourceURL: stagedURL, sourceBytes: bytes))
            } catch {
                notice = L10n.format("notice.import_failed", error.localizedDescription)
            }
            importProgress = ConversionImportProgress(
                completed: index + 1,
                total: uniqueURLs.count,
                currentFileName: nil
            ).mapped(to: progressRange)
        }
        persist()
    }

    public func remove(_ id: UUID) {
        guard !isConverting else { return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        Task {
            let succeeded = await workspace.delete(
                record(item), kind: .video, outputRoot: outputDirectory
            )
            if succeeded {
                items.removeAll { $0.id == id }
            } else {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    public func removeAll() {
        guard !isConverting else { return }
        let removedItems = items
        notice = nil
        Task {
            var deletedIDs = Set<UUID>()
            for item in removedItems {
                if await workspace.delete(record(item), kind: .video, outputRoot: outputDirectory) {
                    deletedIDs.insert(item.id)
                }
            }
            items.removeAll { deletedIDs.contains($0.id) }
            if deletedIDs.count != removedItems.count {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
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
            persist()
        }

        let successes = items.reduce(into: 0) { count, item in
            if case .completed = item.status { count += 1 }
        }
        notice = Task.isCancelled
            ? L10n.string("notice.cancelled")
            : L10n.format("video.notice.completed", successes)
        isConverting = false
        task = nil
        persist()
    }

    private func restore() async {
        guard items.isEmpty, !isConverting else { return }
        let records = await workspace.load(.video)
        items = records.map { record in
            let outputURL = record.outputPath.map { URL(fileURLWithPath: $0) }
            let status: VideoConversionStatus
            switch record.status {
            case .completed where outputURL.map({ FileManager.default.fileExists(atPath: $0.path) }) == true:
                status = .completed(outputURL!)
            case .failed: status = .ready
            case .cancelled: status = .cancelled
            default: status = .ready
            }
            return VideoConversionItem(
                id: record.id,
                sourceURL: URL(fileURLWithPath: record.sourcePath),
                sourceBytes: record.sourceBytes,
                status: status
            )
        }
        persist()
    }

    private func persist() {
        let records = items.map(record)
        Task { await workspace.save(records, kind: .video) }
    }

    private func record(_ item: VideoConversionItem) -> PersistedConversionItem {
        let status: PersistedConversionStatus
        let outputPath: String?
        switch item.status {
        case .completed(let url): status = .completed; outputPath = url.path
        case .failed: status = .failed; outputPath = nil
        case .cancelled: status = .cancelled; outputPath = nil
        case .ready, .converting: status = .ready; outputPath = nil
        }
        return PersistedConversionItem(
            id: item.id,
            sourcePath: item.sourceURL.path,
            sourceBytes: item.sourceBytes,
            status: status,
            outputPath: outputPath
        )
    }

    private static func defaultOutputDirectory() -> URL {
        let manager = FileManager.default
        let base = manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        return base.appendingPathComponent("Converted Videos", isDirectory: true)
    }
}
