// 音频转换及视频提取音轨的状态协调。
// 将输入暂存并检查音轨信息，管理选择、导入进度、顺序转换和工作区恢复。
// 取消会通知转换引擎；删除列表项时仅在工作区清理成功后移除对应状态。
// 音频界面通过该状态对象提交导入与转换操作，并展示每项结果和总体进度。
// 音频引擎、导入调度器和工作区分别负责编码、许可协调及持久化。

import Foundation
import Observation

/// 管理音频输入、转换设置、导入进度和批次结果，并协调工作区与编码引擎。
@MainActor
@Observable
final class AudioConversionViewModel {
    private(set) var items: [AudioConversionItem] = []
    private(set) var isConverting = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var itemProgress = 0.0
    private(set) var notice: String?
    var isPremiumRequiredPresented = false
    private(set) var importProgress: ConversionImportProgress?

    var outputFormat: AudioOutputFormat = .mp3
    var bitRate: AudioBitRate = .high
    let outputDirectory: URL

    private let engine: AudioConversionEngine
    private let workspace = ConversionWorkspace.shared
    @ObservationIgnored private var task: Task<Void, Never>?

    /// 配置音频引擎与默认输出目录，并异步恢复先前工作区。
    init(engine: AudioConversionEngine = AudioConversionEngine()) {
        self.engine = engine
        outputDirectory = ConversionOutputDirectory.url(for: .audio)
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

    var sizeEstimate: ConversionSizeEstimate? {
        ConversionSizeEstimate.audio(
            items: items,
            format: outputFormat,
            bitRate: bitRate
        )
    }

    /// 按来源过滤格式并去重，逐项暂存和检查；检查失败时清理暂存副本，其他输入仍可继续。
    func addFiles(
        _ urls: [URL],
        sourceKind: AudioSourceKind = .audioFile,
        photoAssetIdentifiers: [URL: String] = [:],
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
                    let inspection = try await ConversionImportScheduler.shared.withPermit {
                        try await audioEngine.inspectDetails(stagedURL, sourceKind: sourceKind)
                    }
                    items.append(AudioConversionItem(
                        id: id,
                        sourceURL: stagedURL,
                        sourceBytes: bytes,
                        sourceKind: sourceKind,
                        duration: inspection.duration,
                        sampleRate: inspection.sampleRate,
                        channelCount: inspection.channelCount,
                        photoAssetIdentifier: photoAssetIdentifiers[url.standardizedFileURL]
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

    /// 删除对应工作区记录和文件；只有清理成功后才从列表移除，失败时显示提示。
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

    /// 批量清理工作区，仅移除清理成功的记录，并在部分失败时保留其余项目。
    func removeAll() {
        guard !isConverting else { return }
        let removedItems = items
        notice = nil
        Task {
            let deletedIDs = await workspace.delete(
                removedItems.map(record),
                kind: .audio,
                outputRoot: outputDirectory
            )
            items.removeAll { deletedIDs.contains($0.id) }
            if deletedIDs.count != removedItems.count {
                notice = L10n.string("conversion.delete.failed")
            }
            persist()
        }
    }

    /// 将导入失败信息转换为界面提示。
    func reportImportFailure(_ message: String) {
        notice = L10n.format("notice.import_failed", message)
    }

    /// 先为待转换项目申请使用许可，再同步标记运行状态并启动批次。
    func start(usagePolicy: ConversionUsagePolicy = .unrestricted) {
        guard canConvert else { return }
        let count = items.filter { item in
            switch item.status {
            case .ready, .failed, .cancelled: true
            default: false
            }
        }.count
        guard let permit = usagePolicy.reserve(.audio, count) else {
            isPremiumRequiredPresented = true
            return
        }
        isConverting = true
        task = Task { await run(permit: permit) }
    }

    /// 请求取消当前任务并通知转换引擎停止进行中的操作。
    func cancel() {
        task?.cancel()
        Task { await engine.cancelAll() }
    }

    /// 顺序转换可重试项目，逐项记录进度与结果；结束时释放许可并保存状态。
    private func run(permit: ConversionUsagePermit) async {
        defer { permit.finish() }
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
                permit.recordSuccess()
            } catch let error as AudioConversionError {
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
        notice = Task.isCancelled
            ? L10n.string("notice.cancelled")
            : L10n.format("audio.notice.completed", permit.successfulCount)
        isConverting = false
        task = nil
        persist()
    }

    /// 仅在列表仍为空且没有导入或转换时恢复工作区；输出不存在时不保留已完成状态。
    private func restore() async {
        guard items.isEmpty, !isConverting else { return }
        let records = await workspace.load(.audio)
        guard items.isEmpty, importProgress == nil, !isConverting else { return }
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
                sampleRate: record.sampleRate,
                channelCount: record.channelCount,
                status: status,
                photoAssetIdentifier: record.photoAssetIdentifier
            )
        }
        persist()
    }

    /// 将当前项目状态映射为工作区记录并异步保存。
    private func persist() {
        let records = items.map(record)
        Task { await workspace.save(records, kind: .audio) }
    }

    /// 将界面项目转换为持久化记录，保留源文件、输出及照片来源信息。
    private func record(_ item: AudioConversionItem) -> PersistedConversionItem {
        let persistedState = item.status.persistedState
        return PersistedConversionItem(
            id: item.id,
            sourcePath: item.sourceURL.path,
            sourceBytes: item.sourceBytes,
            status: persistedState.status,
            outputPath: persistedState.outputPath,
            photoAssetIdentifier: item.photoAssetIdentifier,
            sourceKind: item.sourceKind,
            duration: item.duration,
            sampleRate: item.sampleRate,
            channelCount: item.channelCount
        )
    }
}
