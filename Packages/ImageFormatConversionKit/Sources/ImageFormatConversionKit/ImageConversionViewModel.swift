import Foundation
import Observation

public struct ImageConversionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public var info: ImageAssetInfo?
    public var status: ImageConversionItemStatus

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        info: ImageAssetInfo? = nil,
        status: ImageConversionItemStatus = .inspecting
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.info = info
        self.status = status
    }
}

public enum ImageConversionItemStatus: Hashable, Sendable {
    case inspecting
    case ready
    case converting
    case completed(outputURL: URL)
    case failed(message: String)
    case cancelled
}

@MainActor
@Observable
public final class ImageConversionViewModel {
    public private(set) var items: [ImageConversionItem] = []
    public private(set) var availableFormats: [ImageOutputFormat]
    public private(set) var isConverting = false
    public private(set) var progress = ImageBatchProgress(
        completed: 0,
        total: 0,
        succeeded: 0,
        failed: 0,
        lastSourceURL: nil
    )
    public private(set) var notice: String?

    public var outputFormat: ImageOutputFormat
    public var quality = 0.85
    public var metadataPolicy: ImageMetadataPolicy = .removeGPS
    public var resizePreset: ImageResizePreset = .original
    public var flattenColor: ImageFlattenColor = .white
    public var maxConcurrentConversions = 2

    public let outputDirectory: URL

    private let engine: ImageConversionEngine

    private let batchConverter: ImageBatchConverter

    @ObservationIgnored
    private var conversionTask: Task<Void, Never>?

    public init(
        outputDirectory: URL? = nil,
        engine: ImageConversionEngine = ImageConversionEngine()
    ) {
        let formats = ImageConversionEngine.supportedOutputFormats
        availableFormats = formats
        outputFormat = formats.contains(.jpeg) ? .jpeg : (formats.first ?? .png)
        self.outputDirectory = outputDirectory ?? Self.defaultOutputDirectory()
        self.engine = engine
        batchConverter = ImageBatchConverter(engine: engine)
    }

    public var canStartConversion: Bool {
        !isConverting && items.contains(where: Self.isConvertible)
    }

    public var completedCount: Int {
        items.reduce(into: 0) { count, item in
            if case .completed = item.status {
                count += 1
            }
        }
    }

    public func addFiles(_ urls: [URL]) async {
        guard !isConverting else { return }
        notice = nil

        let existingURLs = Set(items.map { $0.sourceURL.standardizedFileURL })
        var seenURLs = existingURLs
        let uniqueURLs = urls.filter { url in
            seenURLs.insert(url.standardizedFileURL).inserted
        }

        guard !uniqueURLs.isEmpty else {
            if !urls.isEmpty {
                notice = L10n.string("notice.duplicates_ignored")
            }
            return
        }

        let newItems = uniqueURLs.map { ImageConversionItem(sourceURL: $0) }
        items.append(contentsOf: newItems)

        await withTaskGroup(of: InspectionOutcome.self) { group in
            let concurrencyLimit = min(4, newItems.count)
            var nextItemIndex = 0

            for _ in 0 ..< concurrencyLimit {
                let item = newItems[nextItemIndex]
                let conversionEngine = engine
                group.addTask {
                    do {
                        return .success(
                            id: item.id,
                            info: try await conversionEngine.inspect(item.sourceURL)
                        )
                    } catch let error as ImageConversionError {
                        return .failure(
                            id: item.id,
                            message: error.localizedDescription
                        )
                    } catch {
                        return .failure(id: item.id, message: error.localizedDescription)
                    }
                }
                nextItemIndex += 1
            }

            for await outcome in group {
                guard let index = items.firstIndex(where: { $0.id == outcome.id }) else {
                    continue
                }

                switch outcome {
                case let .success(_, info):
                    items[index].info = info
                    if info.frameCount == 1 {
                        items[index].status = .ready
                    } else {
                        let error = ImageConversionError.animatedImageUnsupported(
                            frameCount: info.frameCount
                        )
                        items[index].status = .failed(message: error.localizedDescription)
                    }

                case let .failure(_, message):
                    items[index].status = .failed(message: message)
                }

                if nextItemIndex < newItems.count, !Task.isCancelled {
                    let item = newItems[nextItemIndex]
                    let conversionEngine = engine
                    group.addTask {
                        do {
                            return .success(
                                id: item.id,
                                info: try await conversionEngine.inspect(item.sourceURL)
                            )
                        } catch let error as ImageConversionError {
                            return .failure(
                                id: item.id,
                                message: error.localizedDescription
                            )
                        } catch {
                            return .failure(id: item.id, message: error.localizedDescription)
                        }
                    }
                    nextItemIndex += 1
                }
            }
        }
    }

    public func removeItem(id: UUID) {
        guard !isConverting else { return }
        items.removeAll { $0.id == id }
    }

    public func removeAll() {
        guard !isConverting else { return }
        items.removeAll()
        notice = nil
        resetProgress()
    }

    public func clearCompleted() {
        guard !isConverting else { return }
        items.removeAll {
            if case .completed = $0.status { return true }
            return false
        }
    }

    public func startConversion() {
        guard canStartConversion else { return }

        conversionTask?.cancel()
        conversionTask = Task { [weak self] in
            guard let self else { return }
            await runConversion()
        }
    }

    public func cancelConversion() {
        conversionTask?.cancel()
    }

    public func reportImportFailure(_ message: String) {
        notice = L10n.format("notice.import_failed", message)
    }

    private func runConversion() async {
        isConverting = true
        notice = nil
        resetProgress()

        let convertibleIDs = Set(
            items.filter(Self.isConvertible).map(\.id)
        )

        for index in items.indices where convertibleIDs.contains(items[index].id) {
            items[index].status = .converting
        }

        let requests: [ImageConversionRequest] = items.compactMap { item in
            guard convertibleIDs.contains(item.id) else { return nil }
            return ImageConversionRequest(
                sourceURL: item.sourceURL,
                destinationDirectory: outputDirectory,
                outputFormat: outputFormat,
                quality: quality,
                metadataPolicy: metadataPolicy,
                resizePolicy: resizePreset.policy,
                flattenColor: flattenColor,
                collisionPolicy: .makeUnique
            )
        }

        let batchResult = await batchConverter.convert(
            requests,
            maxConcurrentConversions: maxConcurrentConversions,
            progress: { [weak self] progress in
                await self?.apply(progress: progress)
            }
        )

        let successfulOutputs = Dictionary(
            uniqueKeysWithValues: batchResult.successes.map {
                ($0.sourceURL.standardizedFileURL, $0.outputURL)
            }
        )
        let failures = Dictionary(
            uniqueKeysWithValues: batchResult.failures.map {
                ($0.sourceURL.standardizedFileURL, $0.error)
            }
        )

        for index in items.indices where convertibleIDs.contains(items[index].id) {
            let sourceURL = items[index].sourceURL.standardizedFileURL
            if let outputURL = successfulOutputs[sourceURL] {
                items[index].status = .completed(outputURL: outputURL)
            } else if let error = failures[sourceURL] {
                items[index].status = error == .cancelled
                    ? .cancelled
                    : .failed(message: error.localizedDescription)
            } else {
                items[index].status = .cancelled
            }
        }

        if batchResult.wasCancelled {
            notice = L10n.string("notice.cancelled")
        } else if batchResult.failures.isEmpty {
            notice = L10n.format("notice.completed", batchResult.successes.count)
        } else {
            notice = L10n.format(
                "notice.completed_with_failures",
                batchResult.successes.count,
                batchResult.failures.count
            )
        }

        isConverting = false
        conversionTask = nil
    }

    private func apply(progress: ImageBatchProgress) {
        self.progress = progress
    }

    private func resetProgress() {
        progress = ImageBatchProgress(
            completed: 0,
            total: 0,
            succeeded: 0,
            failed: 0,
            lastSourceURL: nil
        )
    }

    private static func isConvertible(_ item: ImageConversionItem) -> Bool {
        guard item.info?.frameCount == 1 else { return false }
        switch item.status {
        case .inspecting, .converting, .completed:
            return false
        case .ready, .failed, .cancelled:
            return true
        }
    }

    private static func defaultOutputDirectory() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("Converted Images", isDirectory: true)
    }
}

private enum InspectionOutcome: Sendable {
    case success(id: UUID, info: ImageAssetInfo)
    case failure(id: UUID, message: String)

    var id: UUID {
        switch self {
        case let .success(id, _), let .failure(id, _): id
        }
    }
}
