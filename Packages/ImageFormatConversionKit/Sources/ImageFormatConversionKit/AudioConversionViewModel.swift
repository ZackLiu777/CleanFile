import Foundation
import Observation

@MainActor
@Observable
final class AudioConversionViewModel {
    private(set) var items: [AudioConversionItem] = []
    private(set) var isConverting = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var itemProgress = 0.0
    private(set) var notice: String?
    private(set) var importProgress: ConversionImportProgress?

    var outputFormat: AudioOutputFormat = .aac
    var bitRate: AudioBitRate = .high
    let outputDirectory: URL

    private let engine: AudioConversionEngine
    private let workspace = ConversionWorkspace.shared
    @ObservationIgnored private var task: Task<Void, Never>?

    init(engine: AudioConversionEngine = AudioConversionEngine()) {
        self.engine = engine
        let manager = FileManager.default
        let base = manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        outputDirectory = base.appendingPathComponent("Converted Audio", isDirectory: true)
        Task { [weak self] in await self?.restore() }
    }

    var canConvert: Bool {
        !isConverting && items.contains {
            switch $0.status {
            case .ready, .failed, .cancelled: true
            case .converting, .completed: false
            }
        }
    }

    func addFiles(
        _ urls: [URL],
        sourceKind: AudioSourceKind = .audioFile,
        progressRange: ClosedRange<Double> = 0 ... 1
    ) async {
        guard !isConverting, importProgress == nil else { return }
        let allowed = Set(
            sourceKind == .video
                ? AudioConversionEngine.supportedVideoInputExtensions
                : AudioConversionEngine.supportedInputExtensions
        )
        let accepted = urls.filter { allowed.contains($0.pathExtension.lowercased()) }
        if accepted.count != urls.count { notice = L10n.string("audio.error.unsupported") }
        var knownURLs = Set(items.map { $0.sourceURL.standardizedFileURL })
        let uniqueURLs = accepted.filter {
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
                    kind: .audio
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
                do {
                    let audioEngine = engine
                    let duration = try await ConversionImportScheduler.shared.withPermit {
                        try await audioEngine.inspect(stagedURL, sourceKind: sourceKind)
                    }
                    items.append(AudioConversionItem(
                        id: id,
                        sourceURL: stagedURL,
                        sourceBytes: bytes,
                        sourceKind: sourceKind,
                        duration: duration
                    ))
                } catch {
                    _ = await workspace.delete(
                        PersistedConversionItem(
                            id: id,
                            sourcePath: stagedURL.path,
                            sourceBytes: bytes,
                            status: .failed,
                            outputPath: nil,
                            sourceKind: sourceKind
                        ),
                        kind: .audio,
                        outputRoot: outputDirectory
                    )
                    throw error
                }
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

    func remove(_ id: UUID) {
        guard !isConverting else { return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        Task {
            let succeeded = await workspace.delete(
                record(item), kind: .audio, outputRoot: outputDirectory
            )
            if succeeded {
                items.removeAll { $0.id == id }
            } else {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    func removeAll() {
        guard !isConverting else { return }
        let removedItems = items
        notice = nil
        Task {
            var deletedIDs = Set<UUID>()
            for item in removedItems {
                if await workspace.delete(record(item), kind: .audio, outputRoot: outputDirectory) {
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

    func reportImportFailure(_ message: String) {
        notice = L10n.format("notice.import_failed", message)
    }

    func start() {
        guard canConvert else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func cancel() {
        task?.cancel()
        Task { await engine.cancelAll() }
    }

    private func run() async {
        isConverting = true
        completed = 0
        itemProgress = 0
        notice = nil
        let candidates = Set(items.compactMap { item -> UUID? in
            switch item.status {
            case .ready, .failed, .cancelled: item.id
            case .converting, .completed: nil
            }
        })
        total = candidates.count

        for index in items.indices where candidates.contains(items[index].id) {
            if Task.isCancelled {
                items[index].status = .cancelled
                continue
            }
            items[index].status = .converting
            itemProgress = 0
            let request = AudioConversionRequest(
                sourceURL: items[index].sourceURL,
                destinationDirectory: outputDirectory,
                outputFormat: outputFormat,
                bitRate: bitRate,
                sourceKind: items[index].sourceKind
            )
            do {
                let url = try await engine.convert(request) { [weak self] value in
                    await MainActor.run { self?.itemProgress = value }
                }
                items[index].status = .completed(url)
            } catch let error as AudioConversionError {
                items[index].status = error == .cancelled
                    ? .cancelled
                    : .failed(error.localizedDescription)
            } catch {
                items[index].status = .failed(error.localizedDescription)
            }
            completed += 1
            persist()
        }
        notice = Task.isCancelled
            ? L10n.string("notice.cancelled")
            : L10n.format("audio.notice.completed", completed)
        isConverting = false
        task = nil
        persist()
    }

    private func restore() async {
        guard items.isEmpty, !isConverting else { return }
        let records = await workspace.load(.audio)
        items = records.map { record in
            let outputURL = record.outputPath.map { URL(fileURLWithPath: $0) }
            let status: AudioConversionStatus
            switch record.status {
            case .completed where outputURL.map({ FileManager.default.fileExists(atPath: $0.path) }) == true:
                status = .completed(outputURL!)
            case .cancelled: status = .cancelled
            default: status = .ready
            }
            return AudioConversionItem(
                id: record.id,
                sourceURL: URL(fileURLWithPath: record.sourcePath),
                sourceBytes: record.sourceBytes,
                sourceKind: record.sourceKind ?? .audioFile,
                duration: record.duration,
                status: status
            )
        }
        persist()
    }

    private func persist() {
        let records = items.map(record)
        Task { await workspace.save(records, kind: .audio) }
    }

    private func record(_ item: AudioConversionItem) -> PersistedConversionItem {
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
            outputPath: outputPath,
            sourceKind: item.sourceKind,
            duration: item.duration
        )
    }
}
