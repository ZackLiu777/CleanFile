//
//  文件职责：协调 ImageConversion 页面状态、用户操作与底层服务。
//  所属模块：ImageFormatConversionKit。
//

import Foundation
import Observation

/// 定义 `ImageConversionItem` 的值语义数据与相关行为。
public struct ImageConversionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public var info: ImageAssetInfo?
    public var status: ImageConversionItemStatus

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
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

/// 定义 `ImageConversionItemStatus` 使用的有限状态或选项集合。
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
/// 封装 `ImageConversionViewModel` 的引用语义、状态与业务行为。
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
    private(set) var importProgress: ConversionImportProgress?

    public var outputFormat: ImageOutputFormat {
        didSet {
            if !outputFormat.supportsTransparentBackground && background == .transparent {
                background = .white
            }
        }
    }
    public var quality = 0.85
    public var metadataPolicy: ImageMetadataPolicy = .removeGPS
    public var resizePreset: ImageResizePreset = .original
    public var flattenColor: ImageFlattenColor = .white
    public var background: ImageBackground = .white
    public var maxConcurrentConversions = 2

    public let outputDirectory: URL

    private let engine: ImageConversionEngine
    private let workspace = ConversionWorkspace.shared

    private let batchConverter: ImageBatchConverter

    @ObservationIgnored
    private var conversionTask: Task<Void, Never>?

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
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
        Task { [weak self] in await self?.restore() }
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

    /// 封装 `addFiles` 对应的局部行为，供当前类型在统一入口下复用。
    public func addFiles(
        _ urls: [URL],
        progressRange: ClosedRange<Double> = 0 ... 1
    ) async {
        guard !isConverting, importProgress == nil else { return }
        notice = nil

        var seenURLs = Set(items.map { $0.sourceURL.standardizedFileURL })
        let uniqueURLs = urls.filter { url in
            seenURLs.insert(url.standardizedFileURL).inserted
        }

        guard !uniqueURLs.isEmpty else {
            if !urls.isEmpty {
                notice = L10n.string("notice.duplicates_ignored")
            }
            return
        }

        importProgress = ConversionImportProgress(
            completed: 0,
            total: uniqueURLs.count,
            currentFileName: uniqueURLs.first?.lastPathComponent
        ).mapped(to: progressRange)
        defer { importProgress = nil }
        var newItems: [ImageConversionItem] = []
        for (index, url) in uniqueURLs.enumerated() {
            if Task.isCancelled { break }
            importProgress = ConversionImportProgress(
                completed: index,
                total: uniqueURLs.count,
                currentFileName: url.lastPathComponent
            ).mapped(to: progressRange)
            let id = UUID()
            do {
                let (stagedURL, _) = try await workspace.stage(
                    url,
                    id: id,
                    kind: .image
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
                let item = ImageConversionItem(id: id, sourceURL: stagedURL)
                newItems.append(item)
                items.append(item)
            } catch is CancellationError {
                break
            } catch {
                notice = L10n.format("notice.import_failed", error.localizedDescription)
            }
            importProgress = ConversionImportProgress(
                completed: index + 1,
                total: uniqueURLs.count,
                currentFileName: nil
            ).mapped(to: progressRange)
        }
        await withTaskGroup(of: InspectionOutcome.self) { group in
            let concurrencyLimit = min(Self.inspectionConcurrencyLimit, newItems.count)
            var nextItemIndex = 0

            for _ in 0 ..< concurrencyLimit {
                let item = newItems[nextItemIndex]
                let conversionEngine = engine
                group.addTask {
                    do {
                        let info = try await ConversionImportScheduler.shared.withPermit {
                            try await conversionEngine.inspect(item.sourceURL)
                        }
                        return .success(
                            id: item.id,
                            info: info
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
                            let info = try await ConversionImportScheduler.shared.withPermit {
                                try await conversionEngine.inspect(item.sourceURL)
                            }
                            return .success(
                                id: item.id,
                                info: info
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
        persist()
    }

    private static var inspectionConcurrencyLimit: Int {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: 1
        case .nominal, .fair: 2
        @unknown default: 1
        }
    }

    /// 执行 `removeItem` 移除流程，并同步更新受影响的业务状态。
    public func removeItem(id: UUID) {
        guard !isConverting else { return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        Task {
            let succeeded = await workspace.delete(
                record(item), kind: .image, outputRoot: outputDirectory
            )
            if succeeded {
                items.removeAll { $0.id == id }
            } else {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    /// 执行 `removeAll` 移除流程，并同步更新受影响的业务状态。
    public func removeAll() {
        guard !isConverting else { return }
        let removedItems = items
        notice = nil
        resetProgress()
        Task {
            var deletedIDs = Set<UUID>()
            for item in removedItems {
                if await workspace.delete(record(item), kind: .image, outputRoot: outputDirectory) {
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

    /// 重置 `clearCompleted` 管理的状态，避免旧任务或旧数据影响下一次操作。
    public func clearCompleted() {
        guard !isConverting else { return }
        let completedItems = items.filter {
            if case .completed = $0.status { true } else { false }
        }
        Task {
            var deletedIDs = Set<UUID>()
            for item in completedItems {
                if await workspace.delete(record(item), kind: .image, outputRoot: outputDirectory) {
                    deletedIDs.insert(item.id)
                }
            }
            items.removeAll { deletedIDs.contains($0.id) }
            if deletedIDs.count != completedItems.count {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    /// 启动 `startConversion` 对应流程，并初始化本轮任务需要的状态。
    public func startConversion() {
        guard canStartConversion else { return }

        conversionTask?.cancel()
        conversionTask = Task { [weak self] in
            guard let self else { return }
            await runConversion()
        }
    }

    /// 取消 `cancelConversion` 对应的进行中任务，并收敛到可继续操作的状态。
    public func cancelConversion() {
        conversionTask?.cancel()
    }

    /// 记录 `reportImportFailure` 产生的结果，并通知依赖该状态的调用方。
    public func reportImportFailure(_ message: String) {
        notice = L10n.format("notice.import_failed", message)
    }

    /// 封装 `runConversion` 对应的局部行为，供当前类型在统一入口下复用。
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
                background: background,
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
        persist()
    }

    /// 更新 `apply` 对应的数据，使界面状态与底层结果保持一致。
    private func apply(progress: ImageBatchProgress) {
        self.progress = progress
    }

    /// 重置 `resetProgress` 管理的状态，避免旧任务或旧数据影响下一次操作。
    private func resetProgress() {
        progress = ImageBatchProgress(
            completed: 0,
            total: 0,
            succeeded: 0,
            failed: 0,
            lastSourceURL: nil
        )
    }

    /// 加载 `restore` 所需的数据，并将结果转换为当前层可消费的状态。
    private func restore() async {
        guard items.isEmpty, !isConverting else { return }
        let records = await workspace.load(.image)
        for record in records {
            let sourceURL = URL(fileURLWithPath: record.sourcePath)
            var item = ImageConversionItem(id: record.id, sourceURL: sourceURL)
            do {
                let info = try await engine.inspect(sourceURL)
                item.info = info
                if record.status == .completed,
                   let outputPath = record.outputPath,
                   FileManager.default.fileExists(atPath: outputPath) {
                    item.status = .completed(outputURL: URL(fileURLWithPath: outputPath))
                } else if info.frameCount == 1 {
                    item.status = record.status == .cancelled ? .cancelled : .ready
                } else {
                    item.status = .failed(message: ImageConversionError
                        .animatedImageUnsupported(frameCount: info.frameCount)
                        .localizedDescription)
                }
            } catch {
                item.status = .failed(message: error.localizedDescription)
            }
            items.append(item)
        }
        persist()
    }

    /// 持久化 `persist` 对应的数据，并保持后续恢复所需的信息完整。
    private func persist() {
        let records = items.map(record)
        Task { await workspace.save(records, kind: .image) }
    }

    /// 记录 `record` 产生的结果，并通知依赖该状态的调用方。
    private func record(_ item: ImageConversionItem) -> PersistedConversionItem {
        let status: PersistedConversionStatus
        let outputPath: String?
        switch item.status {
        case .completed(let url): status = .completed; outputPath = url.path
        case .failed: status = .failed; outputPath = nil
        case .cancelled: status = .cancelled; outputPath = nil
        case .inspecting, .ready, .converting: status = .ready; outputPath = nil
        }
        return PersistedConversionItem(
            id: item.id,
            sourcePath: item.sourceURL.path,
            sourceBytes: item.info?.fileSizeBytes ?? 0,
            status: status,
            outputPath: outputPath
        )
    }

    /// 判断 `isConvertible` 条件是否成立，供调用方选择正确的处理分支。
    private static func isConvertible(_ item: ImageConversionItem) -> Bool {
        guard item.info?.frameCount == 1 else { return false }
        switch item.status {
        case .inspecting, .converting, .completed:
            return false
        case .ready, .failed, .cancelled:
            return true
        }
    }

    /// 封装 `defaultOutputDirectory` 对应的局部行为，供当前类型在统一入口下复用。
    private static func defaultOutputDirectory() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("Converted Images", isDirectory: true)
    }
}

/// 定义 `InspectionOutcome` 使用的有限状态或选项集合。
private enum InspectionOutcome: Sendable {
    case success(id: UUID, info: ImageAssetInfo)
    case failure(id: UUID, message: String)

    var id: UUID {
        switch self {
        case let .success(id, _), let .failure(id, _): id
        }
    }
}
