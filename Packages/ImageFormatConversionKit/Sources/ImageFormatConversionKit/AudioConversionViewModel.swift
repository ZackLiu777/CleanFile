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

    var outputFormat: AudioOutputFormat = .aac
    var bitRate: AudioBitRate = .high
    let outputDirectory: URL

    private let engine: AudioConversionEngine
    @ObservationIgnored private var task: Task<Void, Never>?

    init(engine: AudioConversionEngine = AudioConversionEngine()) {
        self.engine = engine
        let manager = FileManager.default
        let base = manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        outputDirectory = base.appendingPathComponent("Converted Audio", isDirectory: true)
    }

    var canConvert: Bool {
        !isConverting && items.contains {
            switch $0.status {
            case .ready, .failed, .cancelled: true
            case .converting, .completed: false
            }
        }
    }

    func addFiles(_ urls: [URL]) {
        guard !isConverting else { return }
        let allowed = Set(AudioConversionEngine.supportedInputExtensions)
        let accepted = urls.filter { allowed.contains($0.pathExtension.lowercased()) }
        if accepted.count != urls.count { notice = L10n.string("audio.error.unsupported") }
        var known = Set(items.map { $0.sourceURL.standardizedFileURL })
        for url in accepted where known.insert(url.standardizedFileURL).inserted {
            let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            items.append(AudioConversionItem(sourceURL: url, sourceBytes: bytes))
        }
    }

    func remove(_ id: UUID) {
        guard !isConverting else { return }
        items.removeAll { $0.id == id }
    }

    func removeAll() {
        guard !isConverting else { return }
        items.removeAll()
        notice = nil
    }

    func reportImportFailure(_ message: String) {
        notice = L10n.format("notice.import_failed", message)
    }

    func start() {
        guard canConvert else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func cancel() { task?.cancel() }

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
                bitRate: bitRate
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
        }
        notice = Task.isCancelled
            ? L10n.string("notice.cancelled")
            : L10n.format("audio.notice.completed", completed)
        isConverting = false
        task = nil
    }
}
