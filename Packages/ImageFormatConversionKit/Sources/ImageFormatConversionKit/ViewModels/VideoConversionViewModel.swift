// 视频导入、容量估算与批量转换状态。
// 输入暂存后可按设置估算输出大小；批次顺序转换并分别记录结果。
// 新估算取消旧请求，原件替换后的工作区清理也单独报告失败。
// 视频页面通过该对象提交导入、设置和转换请求，并观察进度与结果。
// 视频引擎负责编码，工作区负责输入副本和清单；状态对象协调两者。

import Foundation
import Observation

/// 协调视频导入、输出设置、估算、顺序转换与工作区状态恢复。
@MainActor
@Observable
public final class VideoConversionViewModel {
    public private(set) var items: [VideoConversionItem] = []
    public private(set) var isConverting = false
    public private(set) var completed = 0
    public private(set) var total = 0
    public private(set) var currentProgress = 0.0
    public private(set) var notice: String?
    public var isPremiumRequiredPresented = false
    private(set) var sizeEstimate: ConversionSizeEstimate?
    private(set) var isEstimatingSize = false
    private(set) var importProgress: ConversionImportProgress?

    public var container: VideoOutputContainer = .mp4 {
        didSet { scheduleSizeEstimate() }
    }
    public var codec: VideoCodec = .h264 {
        didSet { scheduleSizeEstimate() }
    }
    public var resolution: VideoResolutionPreset = .original {
        didSet { scheduleSizeEstimate() }
    }
    /// 100% preserves the previous automatic export behavior.
    public var bitRateFraction: Double = 1 {
        didSet { scheduleSizeEstimate() }
    }
    private var effectiveBitRateFraction: Double? {
        guard codec == .h264 || codec == .hevc, bitRateFraction < 1 else { return nil }
        return bitRateFraction
    }
    public let outputDirectory: URL

    private let engine: VideoConversionEngine
    private let workspace = ConversionWorkspace.shared
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var estimateTask: Task<Void, Never>?

    /// 指定输出目录和视频引擎，并异步恢复之前保存的工作区。
    public init(
        outputDirectory: URL? = nil,
        engine: VideoConversionEngine = VideoConversionEngine()
    ) {
        self.outputDirectory = outputDirectory ?? ConversionOutputDirectory.url(for: .video)
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

    public var replaceableOriginalCount: Int { replacementCandidates.count }

    /// 仅将具有照片来源标识、已完成且输出文件存在的视频纳入原件替换审阅。
    var replacementCandidates: [ConversionReplacementCandidate] {
        items.compactMap { item in
            guard let identifier = item.photoAssetIdentifier,
                  case let .completed(outputURL) = item.status,
                  FileManager.default.fileExists(atPath: outputURL.path) else { return nil }
            return ConversionReplacementCandidate(
                id: item.id,
                outputURL: outputURL,
                photoAssetIdentifier: identifier,
                kind: .video,
                sourceBytes: item.sourceBytes,
                outputBytes: Int64((try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            )
        }
    }

    /// 清除已替换项的照片关联并清理工作区；只移除清理成功项，失败时保留并提示。
    func finishReplacement(_ replacedIDs: Set<UUID>) async -> Bool {
        let records = items.filter { replacedIDs.contains($0.id) }.map(record)
        for index in items.indices where replacedIDs.contains(items[index].id) {
            items[index].photoAssetIdentifier = nil
        }
        await workspace.save(items.map(record), kind: .video)
        let deletedIDs = await workspace.delete(records, kind: .video, outputRoot: outputDirectory)
        items.removeAll { deletedIDs.contains($0.id) }
        let succeeded = deletedIDs.count == records.count
        if !succeeded { notice = L10n.string("conversion.delete.failed") }
        scheduleSizeEstimate()
        persist()
        return succeeded
    }

    public var availableContainers: [VideoOutputContainer] {
        switch codec {
        case .proRes422, .proRes4444: [.mov]
        case .hevc: [.mp4, .mov]
        case .h264: VideoOutputContainer.allCases
        }
    }

    /// 过滤支持的扩展名并去重，逐项暂存视频；返回成功导入的原始 URL 并刷新大小估算。
    @discardableResult
    public func addFiles(
        _ urls: [URL],
        photoAssetIdentifiers: [URL: String] = [:],
        progressRange: ClosedRange<Double> = 0 ... 1
    ) async -> Set<URL> {
        guard !isConverting, importProgress == nil else { return [] }
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
        guard !uniqueURLs.isEmpty else { return [] }
        importProgress = ConversionImportProgress(
            completed: 0,
            total: uniqueURLs.count,
            currentFileName: uniqueURLs.first?.lastPathComponent
        ).mapped(to: progressRange)
        defer { importProgress = nil }
        var importedURLs = Set<URL>()
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
                items.append(VideoConversionItem(
                    id: id,
                    sourceURL: stagedURL,
                    sourceBytes: bytes,
                    photoAssetIdentifier: photoAssetIdentifiers[url.standardizedFileURL]
                ))
                importedURLs.insert(url.standardizedFileURL)
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
        scheduleSizeEstimate()
        return importedURLs
    }

    /// 清理指定项目的工作区文件；清理成功才移除并更新大小估算。
    public func remove(_ id: UUID) {
        guard !isConverting else { return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        Task {
            let succeeded = await workspace.delete(
                record(item), kind: .video, outputRoot: outputDirectory
            )
            if succeeded {
                items.removeAll { $0.id == id }
                scheduleSizeEstimate()
            } else {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    /// 批量清理工作区，仅移除清理成功的项目，并在部分失败时提示。
    public func removeAll() {
        guard !isConverting else { return }
        let removedItems = items
        notice = nil
        Task {
            let deletedIDs = await workspace.delete(
                removedItems.map(record),
                kind: .video,
                outputRoot: outputDirectory
            )
            items.removeAll { deletedIDs.contains($0.id) }
            scheduleSizeEstimate()
            if deletedIDs.count != removedItems.count {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    /// 将导入失败信息转换为界面提示。
    public func reportImportFailure(_ message: String) {
        notice = L10n.format("notice.import_failed", message)
    }

    /// 以快捷预设发起转换，不改写界面中保存的专业设置。
    public func startQuickCompression(usagePolicy: ConversionUsagePolicy = .unrestricted) {
        start(usagePolicy: usagePolicy, usingQuickPreset: true)
    }

    /// 为可转换项目申请使用许可，并在调度批次前同步标记运行状态。
    public func start(usagePolicy: ConversionUsagePolicy = .unrestricted, usingQuickPreset: Bool = false) {
        guard canConvert else { return }
        let count = items.filter { item in
            switch item.status {
            case .ready, .failed, .cancelled: true
            default: false
            }
        }.count
        guard let permit = usagePolicy.reserve(.video, count) else {
            isPremiumRequiredPresented = true
            return
        }
        isConverting = true
        task = Task { await run(permit: permit, usingQuickPreset: usingQuickPreset) }
    }

    /// 请求取消当前任务并通知视频引擎停止进行中的操作。
    public func cancel() {
        task?.cancel()
        Task { await engine.cancelAll() }
    }

    /// 顺序转换候选视频，按项目记录结果与使用成功次数；取消后剩余项目标记为已取消。
    private func run(permit: ConversionUsagePermit, usingQuickPreset: Bool) async {
        defer { permit.finish() }
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
                container: usingQuickPreset ? .mp4 : container,
                codec: usingQuickPreset ? .hevc : codec,
                resolution: usingQuickPreset ? .original : resolution,
                bitRateFraction: usingQuickPreset ? 0.5 : effectiveBitRateFraction
            )
            do {
                let result = try await engine.convert(request) { [weak self] value in
                    await MainActor.run { self?.currentProgress = value }
                }
                items[index].status = .completed(result.outputURL)
                permit.recordSuccess()
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
            if candidateIDs.contains(item.id), case .completed = item.status { count += 1 }
        }
        notice = Task.isCancelled
            ? L10n.string("notice.cancelled")
            : L10n.format("video.notice.completed", successes)
        isConverting = false
        task = nil
        persist()
    }

    /// 仅在没有新导入或转换时恢复工作区；缺失输出不会被当作已完成结果。
    private func restore() async {
        guard items.isEmpty, !isConverting else { return }
        let records = await workspace.load(.video)
        // A user can finish an import while the manifest is being read. Never
        // replace those live items with the older restored snapshot.
        guard items.isEmpty, importProgress == nil, !isConverting else { return }
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
                status: status,
                photoAssetIdentifier: record.photoAssetIdentifier
            )
        }
        persist()
        scheduleSizeEstimate()
    }

    /// 取消旧估算并等待设置稳定，再按当前输入和参数估算；取消或失败时不发布过期数值。
    private func scheduleSizeEstimate() {
        estimateTask?.cancel()
        sizeEstimate = nil
        guard !items.isEmpty else {
            isEstimatingSize = false
            return
        }

        let sources = items.map { ($0.sourceURL, $0.sourceBytes) }
        let container = container
        let codec = codec
        let resolution = resolution
        let bitRateFraction = effectiveBitRateFraction
        let outputDirectory = outputDirectory
        let engine = engine
        isEstimatingSize = true

        estimateTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                var estimatedBytes: Int64 = 0
                for (sourceURL, _) in sources {
                    try Task.checkCancellation()
                    let request = VideoConversionRequest(
                        sourceURL: sourceURL,
                        destinationDirectory: outputDirectory,
                        container: container,
                        codec: codec,
                        resolution: resolution,
                        bitRateFraction: bitRateFraction
                    )
                    estimatedBytes += try await engine.estimateOutputBytes(request)
                }
                try Task.checkCancellation()
                let originalBytes = sources.reduce(Int64(0)) { $0 + $1.1 }
                self?.sizeEstimate = ConversionSizeEstimate.video(
                    originalBytes: originalBytes,
                    estimatedBytes: estimatedBytes
                )
                self?.isEstimatingSize = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.sizeEstimate = nil
                self?.isEstimatingSize = false
            }
        }
    }

    /// 将当前项目状态映射为工作区记录并异步保存。
    private func persist() {
        let records = items.map(record)
        Task { await workspace.save(records, kind: .video) }
    }

    /// 将视频项目的状态、文件路径和照片来源映射为持久化记录。
    private func record(_ item: VideoConversionItem) -> PersistedConversionItem {
        let persistedState = item.status.persistedState
        return PersistedConversionItem(
            id: item.id,
            sourcePath: item.sourceURL.path,
            sourceBytes: item.sourceBytes,
            status: persistedState.status,
            outputPath: persistedState.outputPath,
            photoAssetIdentifier: item.photoAssetIdentifier
        )
    }
}
