// 图片导入、检查、批量转换及结果状态。
// 输入先暂存，检查与转换使用有界并发；单张结果分别记录成功、失败和取消。
// 照片原件替换后的工作区清理与转换本身分开，避免把清理失败当作完全成功。
// 图片页面通过该对象更新输出选项、启动批处理及读取每个项目的展示状态。
// 源文件的暂存与恢复交由工作区，具体解码编码交给图片引擎。

import Foundation
import Observation

/// 保存暂存源文件、检查信息、转换状态及可选的照片资源标识。
public struct ImageConversionItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public var info: ImageAssetInfo?
    public var status: ImageConversionItemStatus
    public internal(set) var photoAssetIdentifier: String?

    /// 保存图片源地址、可选检查结果、当前状态和照片资源标识。
    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        info: ImageAssetInfo? = nil,
        status: ImageConversionItemStatus = .inspecting,
        photoAssetIdentifier: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.info = info
        self.status = status
        self.photoAssetIdentifier = photoAssetIdentifier
    }
}

/// 区分检查、就绪、转换中、完成、失败和取消，供列表展示和重试判断使用。
public enum ImageConversionItemStatus: Hashable, Sendable {
    case inspecting
    case ready
    case converting
    case completed(outputURL: URL)
    case failed(message: String)
    case cancelled
}

/// 协调图片暂存、资源检查、有界批量转换、使用许可和持久化状态。
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
    public var isPremiumRequiredPresented = false
    private(set) var importProgress: ConversionImportProgress?

    public var outputFormat: ImageOutputFormat {
        didSet {
            if !outputFormat.supportsTransparentBackground && background == .transparent {
                background = .white
            }
        }
    }
    public var quality = 0.9
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

    /// 选择可用输出格式，配置输出目录及引擎，并异步恢复工作区。
    public init(
        outputDirectory: URL? = nil,
        engine: ImageConversionEngine = ImageConversionEngine()
    ) {
        let formats = ImageConversionEngine.supportedOutputFormats
        availableFormats = formats
        outputFormat = formats.contains(.jpeg) ? .jpeg : (formats.first ?? .png)
        self.outputDirectory = outputDirectory ?? ConversionOutputDirectory.url(for: .image)
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

    public var replaceableOriginalCount: Int {
        replacementCandidates.count
    }

    /// 仅将具有照片来源标识、已完成且输出文件存在的图片纳入原件替换审阅。
    var replacementCandidates: [ConversionReplacementCandidate] {
        items.compactMap { item in
            guard let identifier = item.photoAssetIdentifier,
                  case let .completed(outputURL) = item.status,
                  FileManager.default.fileExists(atPath: outputURL.path) else { return nil }
            return ConversionReplacementCandidate(
                id: item.id,
                outputURL: outputURL,
                photoAssetIdentifier: identifier,
                kind: .image,
                sourceBytes: item.info?.fileSizeBytes ?? 0,
                outputBytes: Int64((try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            )
        }
    }

    /// 记录已替换项不再关联照片原件，再清理对应工作区文件；清理失败时保留未删除项并提示。
    func finishReplacement(_ replacedIDs: Set<UUID>) async -> Bool {
        let records = items.filter { replacedIDs.contains($0.id) }.map(record)
        for index in items.indices where replacedIDs.contains(items[index].id) {
            items[index].photoAssetIdentifier = nil
        }
        await workspace.save(items.map(record), kind: .image)
        let deletedIDs = await workspace.delete(records, kind: .image, outputRoot: outputDirectory)
        items.removeAll { deletedIDs.contains($0.id) }
        let succeeded = deletedIDs.count == records.count
        if !succeeded { notice = L10n.string("conversion.delete.failed") }
        persist()
        return succeeded
    }

    var sizeEstimate: ConversionSizeEstimate? {
        ConversionSizeEstimate.image(
            infos: items.compactMap(\.info),
            format: outputFormat,
            quality: quality,
            resize: resizePreset,
            metadata: metadataPolicy
        )
    }

    /// 去重并逐项暂存输入，按热状态限制并发检查；返回成功暂存的原始 URL，单项失败不阻止其他项。
    @discardableResult
    public func addFiles(
        _ urls: [URL],
        photoAssetIdentifiers: [URL: String] = [:],
        progressRange: ClosedRange<Double> = 0 ... 1
    ) async -> Set<URL> {
        guard !isConverting, importProgress == nil else { return [] }
        notice = nil

        var seenURLs = Set(items.map { $0.sourceURL.standardizedFileURL })
        let uniqueURLs = urls.filter { url in
            seenURLs.insert(url.standardizedFileURL).inserted
        }

        guard !uniqueURLs.isEmpty else {
            if !urls.isEmpty {
                notice = L10n.string("notice.duplicates_ignored")
            }
            return []
        }

        importProgress = ConversionImportProgress(
            completed: 0,
            total: uniqueURLs.count,
            currentFileName: uniqueURLs.first?.lastPathComponent
        ).mapped(to: progressRange)
        defer { importProgress = nil }
        var newItems: [ImageConversionItem] = []
        var importedURLs = Set<URL>()
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
                let item = ImageConversionItem(
                    id: id,
                    sourceURL: stagedURL,
                    photoAssetIdentifier: photoAssetIdentifiers[url.standardizedFileURL]
                )
                newItems.append(item)
                items.append(item)
                importedURLs.insert(url.standardizedFileURL)
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
        return importedURLs
    }

    /// 根据设备热状态限制并发检查数量，避免大量图片同时占用资源。
    private static var inspectionConcurrencyLimit: Int {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: 1
        case .nominal, .fair: 2
        @unknown default: 1
        }
    }

    /// 清理指定项目的工作区文件；清理成功才从列表移除，失败时提示。
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

    /// 批量清理工作区，仅移除清理成功的记录，并在部分失败时保留其余项目。
    public func removeAll() {
        guard !isConverting else { return }
        let removedItems = items
        notice = nil
        resetProgress()
        Task {
            let deletedIDs = await workspace.delete(
                removedItems.map(record),
                kind: .image,
                outputRoot: outputDirectory
            )
            items.removeAll { deletedIDs.contains($0.id) }
            if deletedIDs.count != removedItems.count {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    /// 只清理已完成项目，保留未成功删除的记录并提示失败。
    public func clearCompleted() {
        guard !isConverting else { return }
        let completedItems = items.filter {
            if case .completed = $0.status { true } else { false }
        }
        Task {
            let deletedIDs = await workspace.delete(
                completedItems.map(record),
                kind: .image,
                outputRoot: outputDirectory
            )
            items.removeAll { deletedIDs.contains($0.id) }
            if deletedIDs.count != completedItems.count {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    /// 使用快捷压缩预设发起同一转换流程，不覆盖用户保留的专业设置。
    public func startQuickCompression(usagePolicy: ConversionUsagePolicy = .unrestricted) {
        startConversion(usagePolicy: usagePolicy, usingQuickPreset: true)
    }

    /// 根据可转换项申请使用许可，调度任务前先锁定状态，防止重复启动批次。
    public func startConversion(usagePolicy: ConversionUsagePolicy = .unrestricted, usingQuickPreset: Bool = false) {
        guard canStartConversion else { return }
        let count = items.filter(Self.isConvertible).count
        guard let permit = usagePolicy.reserve(.images, count) else {
            isPremiumRequiredPresented = true
            return
        }
        // Lock synchronously, before the Task is scheduled, to prevent duplicate batches.
        isConverting = true
        conversionTask = Task { await runConversion(permit: permit, usingQuickPreset: usingQuickPreset) }
    }

    /// 请求取消图片批次；最终逐项状态由批量转换结果决定。
    public func cancelConversion() {
        conversionTask?.cancel()
    }

    /// 将导入失败信息转换为界面提示。
    public func reportImportFailure(_ message: String) {
        notice = L10n.format("notice.import_failed", message)
    }

    /// 生成不覆盖现有输出的请求并执行有界批处理，再按源 URL 对应更新成功、失败和取消状态。
    private func runConversion(permit: ConversionUsagePermit, usingQuickPreset: Bool) async {
        defer { permit.finish() }
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
                outputFormat: usingQuickPreset ? (availableFormats.contains(.heic) ? .heic : .jpeg) : outputFormat,
                quality: usingQuickPreset ? 0.5 : quality,
                metadataPolicy: usingQuickPreset ? .removeGPS : metadataPolicy,
                resizePolicy: usingQuickPreset ? ImageResizePreset.original.policy : resizePreset.policy,
                flattenColor: flattenColor,
                background: background,
                collisionPolicy: .makeUnique
            )
        }

        let batchResult = await batchConverter.convert(
            requests,
            maxConcurrentConversions: maxConcurrentConversions,
            progress: { [weak self] progress in
                await self?.apply(progress: progress, permit: permit)
            }
        )
        permit.recordSuccess(batchResult.successes.count - permit.successfulCount)

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

    /// 发布批次进度并按新增成功数量记入使用许可。
    private func apply(progress: ImageBatchProgress, permit: ConversionUsagePermit) {
        permit.recordSuccess(progress.succeeded - permit.successfulCount)
        self.progress = progress
    }

    /// 清空上一轮批次的进度统计。
    private func resetProgress() {
        progress = ImageBatchProgress(
            completed: 0,
            total: 0,
            succeeded: 0,
            failed: 0,
            lastSourceURL: nil
        )
    }

    /// 重新检查已保存源文件，仅恢复仍存在的完成输出；恢复期间若已有新导入则不覆盖当前列表。
    private func restore() async {
        guard items.isEmpty, !isConverting else { return }
        let records = await workspace.load(.image)
        guard items.isEmpty, importProgress == nil, !isConverting else { return }
        var restoredItems: [ImageConversionItem] = []
        for record in records {
            let sourceURL = URL(fileURLWithPath: record.sourcePath)
            var item = ImageConversionItem(
                id: record.id,
                sourceURL: sourceURL,
                photoAssetIdentifier: record.photoAssetIdentifier
            )
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
            restoredItems.append(item)
        }
        guard items.isEmpty, importProgress == nil, !isConverting else { return }
        items = restoredItems
        persist()
    }

    /// 将当前项目状态映射为工作区记录并异步保存。
    private func persist() {
        let records = items.map(record)
        Task { await workspace.save(records, kind: .image) }
    }

    /// 将图片项目的状态、文件路径和照片来源映射为持久化记录。
    private func record(_ item: ImageConversionItem) -> PersistedConversionItem {
        let persistedState = item.status.persistedState
        return PersistedConversionItem(
            id: item.id,
            sourcePath: item.sourceURL.path,
            sourceBytes: item.info?.fileSizeBytes ?? 0,
            status: persistedState.status,
            outputPath: persistedState.outputPath,
            photoAssetIdentifier: item.photoAssetIdentifier
        )
    }

    /// 仅允许检查为单帧且处于就绪、失败或取消状态的项目进入批次。
    private static func isConvertible(_ item: ImageConversionItem) -> Bool {
        guard item.info?.frameCount == 1 else { return false }
        switch item.status {
        case .inspecting, .converting, .completed:
            return false
        case .ready, .failed, .cancelled:
            return true
        }
    }

}

/// 携带图片检查成功或失败及项目标识，便于并发完成后更新正确的列表项。
private enum InspectionOutcome: Sendable {
    case success(id: UUID, info: ImageAssetInfo)
    case failure(id: UUID, message: String)

    var id: UUID {
        switch self {
        case let .success(id, _), let .failure(id, _): id
        }
    }
}
