// 存储扫描、恢复、删除与持久化状态的协调。
// 大量快照重建工作在后台进行；安全作用域访问随来源切换维护，删除只更新实际成功的结果。
// 页面通过此模型发起扫描、恢复和用户确认后的删除，并订阅进度与错误状态。
// 持久化恢复和删除后的派生统计在后台准备；释放模型时取消任务并释放授权访问。

//
//  FileScannerViewModel.swift
//  CleanMyIPhone
//


import Combine
import Foundation

/// 后台恢复完成后一次性交付给主线程的扫描状态及其派生汇总。
nonisolated struct PreparedFileState: Sendable {
    let rootURL: URL
    let selectedDirectoryName: String
    let directoryBookmark: Data
    let shouldRewriteSnapshot: Bool
    let skippedFileCount: Int
    let files: [ScannedFile]
    let summary: StorageSummary
    let fileTree: FileNode
    let largestFiles: [ScannedFile]
}

/// 从持久化书签和文件快照重建目录、汇总与最大文件列表，不依赖主线程状态。
nonisolated enum FileStateRestorer {
    /// 解析书签并重建文件、统计和目录树；取消或书签失效时不发布部分结果。
    static func prepare(_ snapshot: FileStateSnapshot) -> PreparedFileState? {
        guard !Task.isCancelled else { return nil }

        let bookmarkInterval = StoragePerformance.begin("Storage Bookmark Resolve")
        var isStale = false
        guard let restoredRoot = try? URL(
            resolvingBookmarkData: snapshot.directoryBookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            StoragePerformance.end("Storage Bookmark Resolve", id: bookmarkInterval)
            return nil
        }

        let hasAccess = restoredRoot.startAccessingSecurityScopedResource()
        defer { if hasAccess { restoredRoot.stopAccessingSecurityScopedResource() } }
        let bookmark = isStale && hasAccess
            ? (try? restoredRoot.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )) ?? snapshot.directoryBookmark
            : snapshot.directoryBookmark
        StoragePerformance.end("Storage Bookmark Resolve", id: bookmarkInterval)

        let reconstructionInterval = StoragePerformance.begin("Storage State Reconstruct")
        var restoredFiles: [ScannedFile] = []
        restoredFiles.reserveCapacity(snapshot.files.count)
        var summaryAccumulator = StorageSummaryAccumulator()
        var treeAccumulator = FileTreeAccumulator(rootURL: restoredRoot)
        var largestFilesAccumulator = LargestFilesAccumulator(limit: 10)

        for (index, persistedFile) in snapshot.files.enumerated() {
            if index.isMultiple(of: 128), Task.isCancelled {
                StoragePerformance.end("Storage State Reconstruct", id: reconstructionInterval)
                return nil
            }
            guard !persistedFile.relativePathComponents.isEmpty else { continue }

            let relativePath = persistedFile.relativePathComponents.joined(separator: "/")
            let restoredURL = restoredRoot.appending(path: relativePath)
            let file = ScannedFile(
                url: restoredURL,
                name: persistedFile.name,
                relativePathComponents: persistedFile.relativePathComponents,
                category: persistedFile.category,
                byteCount: persistedFile.byteCount,
                hasKnownByteCount: persistedFile.hasKnownByteCount,
                creationDate: persistedFile.creationDate,
                modificationDate: persistedFile.modificationDate
            )
            restoredFiles.append(file)
            summaryAccumulator.append(file)
            treeAccumulator.append(file)
            largestFilesAccumulator.append(file)
        }
        StoragePerformance.end("Storage State Reconstruct", id: reconstructionInterval)

        let finalizeInterval = StoragePerformance.begin("Storage State Finalize")
        let prepared = PreparedFileState(
            rootURL: restoredRoot,
            selectedDirectoryName: snapshot.selectedDirectoryName,
            directoryBookmark: bookmark,
            shouldRewriteSnapshot: isStale || snapshot.requiresRewrite,
            skippedFileCount: snapshot.skippedFileCount,
            files: restoredFiles,
            summary: summaryAccumulator.makeSummary(),
            fileTree: treeAccumulator.makeTree(),
            largestFiles: largestFilesAccumulator.sortedDescending()
        )
        StoragePerformance.end("Storage State Finalize", id: finalizeInterval)

        return prepared
    }
}

/// 删除后重算的剩余文件、统计和文件树，供界面一次性更新。
nonisolated struct PreparedDerivedFileState: Sendable {
    let files: [ScannedFile]
    let summary: StorageSummary
    let fileTree: FileNode
    let largestFiles: [ScannedFile]
}

/// 在后台根据实际删除结果重建剩余文件及其派生展示状态。
nonisolated enum DerivedFileStateBuilder {
    /// Rebuilds deletion results independently from MainActor because a selected
    /// category may contain tens of thousands of files. The stages deliberately
    /// mirror the faster contiguous collection operations measured by the
    /// performance suite instead of forcing an interleaved single pass.
    static func prepare(
        files: [ScannedFile],
        excluding deletedURLs: Set<URL>,
        rootURL: URL
    ) -> PreparedDerivedFileState? {
        guard !Task.isCancelled else { return nil }
        let retainedFiles = files.filter { !deletedURLs.contains($0.url) }
        guard !Task.isCancelled else { return nil }
        let summary = StorageSummary(files: retainedFiles)
        guard !Task.isCancelled else { return nil }
        let largestFiles = StorageSelectionAlgorithms.largest(retainedFiles)
        guard !Task.isCancelled else { return nil }
        let fileTree = FileTreeBuilder.build(rootURL: rootURL, files: retainedFiles)
        guard !Task.isCancelled else { return nil }

        return PreparedDerivedFileState(
            files: retainedFiles,
            summary: summary,
            fileTree: fileTree,
            largestFiles: largestFiles
        )
    }
}

/// 协调扫描来源、状态恢复、文件删除和持久化，并发布供存储页面使用的结果。
@MainActor
final class FileScannerViewModel: ObservableObject {
    @Published private(set) var state: ScanState = .idle
    @Published private(set) var files: [ScannedFile] = []
    @Published private(set) var filesRevision = 0
    @Published private(set) var summary: StorageSummary?
    @Published private(set) var fileTree: FileNode?
    @Published private(set) var largestFiles: [ScannedFile] = []
    @Published private(set) var selectedDirectoryName: String?
    @Published private(set) var selectedSourceCount = 0
    @Published private(set) var isSourceSelection = false
    @Published private(set) var deletionState: FileDeletionState = .idle
    @Published private(set) var isRestoringStoredFiles = false

    /// An entitlement change does not itself select or populate a real storage source.
    var hasSelectedStorageSource: Bool {
        selectedDirectoryName != nil || isSourceSelection || summary != nil || fileTree != nil
    }

    private let canUseStorage: () -> Bool
    private let scanner: MetadataFileScanner
    private var scanTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var hasAttemptedRestore = false
    private let deletionService = FileDeletionService()
    private let stateStore = AppStateStore.shared
    private var selectedDirectoryURL: URL?
    private var selectedSourceURLs: [URL] = []
    private var activeSourceAccessURLs: [URL] = []
    private var selectedDirectoryBookmark: Data?
    private var skippedFileCount = 0
    private var restoredDashboardAvailable = false

    /// 注入元数据扫描器和存储功能权限检查，供后续扫描与删除流程使用。
    init(scanner: MetadataFileScanner = MetadataFileScanner(), canUseStorage: @escaping () -> Bool = { true }) {
        self.scanner = scanner
        self.canUseStorage = canUseStorage
    }

    /// 释放 ViewModel 时取消尚未结束的扫描，避免后台任务继续持有无效页面状态。
    deinit {
        scanTask?.cancel()
        restoreTask?.cancel()
        persistenceTask?.cancel()
        activeSourceAccessURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    /// 先获取新来源的安全作用域访问，再释放旧来源，避免重扫同一目录时出现访问间隙。
    private func retainSourceAccess(to sources: [URL]) {
        // Acquire the next grants before releasing old ones, including when
        // rescanning the same folder. Keep the original picker/bookmark URLs.
        let acquired = sources.filter { $0.startAccessingSecurityScopedResource() }
        activeSourceAccessURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        activeSourceAccessURLs = acquired
    }

    /// Restores the previous scan only when the storage experience is opened.
    /// Decoding happens in the store actor and all O(n) reconstruction remains
    /// off MainActor; the UI receives one prepared result at the end.
    func loadIfNeeded() {
        guard canUseStorage() else { return }
        guard !hasAttemptedRestore else { return }
        hasAttemptedRestore = true
        isRestoringStoredFiles = true

        restoreTask = Task { [weak self] in
            defer { self?.isRestoringStoredFiles = false }
            let dashboard = await AppStateStore.shared.loadStorageDashboard()
            guard !Task.isCancelled else { return }
            if let dashboard {
                self?.applyCachedDashboard(dashboard)
            }

            guard let snapshot = await AppStateStore.shared.loadFileState() else { return }
            guard !Task.isCancelled else { return }

            let worker = Task.detached(priority: .userInitiated) {
                FileStateRestorer.prepare(snapshot)
            }
            let prepared = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            guard let self, let prepared, !Task.isCancelled else { return }
            self.applyRestoredState(prepared)
        }
    }

    /// 取消旧扫描和恢复任务，记录单目录书签，清空旧结果并开始接收新扫描事件。
    func scan(directory: URL) {
        guard canUseStorage() else { return }
        retainSourceAccess(to: [directory])
        hasAttemptedRestore = true
        restoreTask?.cancel()
        restoreTask = nil
        persistenceGeneration &+= 1
        persistenceTask?.cancel()
        persistenceTask = nil
        isRestoringStoredFiles = false
        scanTask?.cancel()
        selectedDirectoryName = directory.lastPathComponent
        selectedDirectoryURL = directory
        selectedSourceURLs = [directory]
        selectedSourceCount = 1
        isSourceSelection = false
        selectedDirectoryBookmark = try? directory.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        skippedFileCount = 0
        Task {
            await stateStore.saveStorageDashboard(nil)
            await stateStore.saveFileState(nil)
        }
        files = []
        filesRevision &+= 1
        summary = nil
        fileTree = nil
        largestFiles = []
        state = .scanning(ScanProgress(scannedFileCount: 0, scannedByteCount: 0))

        let events = scanner.scan(directory: directory)
        consume(events)
    }

    /// 去重用户选中的文件和文件夹并启动会话扫描；多来源不生成单目录持久化快照。
    func scan(sources: [URL]) {
        guard canUseStorage() else { return }
        let uniqueSources = StorageSelectionAlgorithms.sources(sources)
        guard !uniqueSources.isEmpty else {
            reportSelectionFailure()
            return
        }
        retainSourceAccess(to: uniqueSources)
        hasAttemptedRestore = true
        restoreTask?.cancel()
        restoreTask = nil
        persistenceGeneration &+= 1
        persistenceTask?.cancel()
        persistenceTask = nil
        isRestoringStoredFiles = false
        scanTask?.cancel()
        selectedSourceURLs = uniqueSources
        selectedSourceCount = uniqueSources.count
        isSourceSelection = true
        selectedDirectoryURL = nil
        selectedDirectoryBookmark = nil
        selectedDirectoryName = uniqueSources.count == 1
            ? uniqueSources[0].lastPathComponent
            : String.localizedStringWithFormat(
                AppL10n.string("%lld selected files"),
                Int64(uniqueSources.count)
            )
        skippedFileCount = 0
        files = []
        filesRevision &+= 1
        summary = nil
        fileTree = nil
        largestFiles = []
        state = .scanning(ScanProgress(scannedFileCount: 0, scannedByteCount: 0))

        Task {
            await stateStore.saveStorageDashboard(nil)
            await stateStore.saveFileState(nil)
        }

        consume(scanner.scan(sources: uniqueSources))
    }

    /// 消费扫描进度与完成事件；区分用户取消、已知扫描错误和其他枚举失败。
    private func consume(_ events: AsyncThrowingStream<FileScanEvent, Error>) {
        scanTask = Task { [weak self] in
            do {
                for try await event in events {
                    guard !Task.isCancelled else { return }
                    self?.handle(event)
                }
            } catch let error as FileScanError {
                guard let self, error != .cancelled else { return }
                self.state = .failure(error)
            } catch is CancellationError {
                // Cancellation is represented by cancelScan() when initiated by the user.
            } catch {
                self?.state = .failure(.unableToEnumerate)
            }
        }
    }

    /// 仅在扫描中取消当前任务，并将页面状态置为已取消。
    func cancelScan() {
        guard state.isScanning else { return }
        scanTask?.cancel()
        scanTask = nil
        state = .cancelled
    }

    /// 区分系统选择器取消与选择失败，向界面发布对应状态。
    func reportSelectionFailure(error: Error? = nil) {
        if let error, (error as NSError).code == NSUserCancelledError {
            state = .cancelled
        } else {
            state = .failure(.selectionFailed)
        }
    }

    /// 重新校验权限、来源和当前扫描中的全部目标，再交给删除服务；失败和取消分别反馈。
    func deleteFiles(withURLs selectedURLs: Set<URL>) async {
        guard canUseStorage() else { return }
        guard !selectedURLs.isEmpty else {
            deletionState = .failure(.noItemsSelected)
            return
        }
        guard !selectedSourceURLs.isEmpty else {
            deletionState = .failure(.folderAccessUnavailable)
            return
        }

        let knownFiles = files.filter { selectedURLs.contains($0.url) }
        guard knownFiles.count == selectedURLs.count else {
            #if DEBUG
            debugPrint("Storage deletion rejected: selection no longer matches current scan")
            #endif
            deletionState = .failure(.invalidSelection)
            return
        }

        deletionState = .deleting(itemCount: knownFiles.count)
        do {
            let result = try await deletionService.delete(
                files: knownFiles,
                selectedRoots: selectedSourceURLs
            )
            await applyDeletion(result)
        } catch let error as FileDeletionError {
            deletionState = .failure(error)
        } catch is CancellationError {
            deletionState = .idle
        } catch {
            deletionState = .failure(.deletionFailed)
        }
    }

    /// 仅在没有删除操作进行时清除上次删除结果。
    func clearDeletionResult() {
        guard !deletionState.isDeleting else { return }
        deletionState = .idle
    }

    /// 将扫描进度或完整结果映射为界面状态；有跳过项时保留部分失败信息。
    private func handle(_ event: FileScanEvent) {
        switch event {
        case .progress(let progress):
            state = .scanning(progress)
        case .completed(let result):
            files = result.files
            filesRevision &+= 1
            summary = result.summary
            fileTree = result.fileTree
            largestFiles = result.largestFiles

            if result.files.isEmpty && result.failures.isEmpty {
                state = .empty
            } else if result.failures.isEmpty {
                state = .success(result.summary)
            } else {
                state = .partialFailure(result.summary, skippedFileCount: result.failures.count)
            }
            skippedFileCount = result.failures.count
            persistStableState()
        }
    }

    /// 后台重建删除后的统计和文件树，只移除确认删除的 URL，并区分成功、失败和部分成功。
    private func applyDeletion(_ result: FileDeletionResult) async {
        guard !selectedSourceURLs.isEmpty else {
            deletionState = .failure(.folderAccessUnavailable)
            return
        }

        let treeRootURL = selectedDirectoryURL
            ?? URL(fileURLWithPath: "/Selected Sources", isDirectory: true)

        let currentFiles = files
        let worker = Task.detached(priority: .userInitiated) {
            let interval = StoragePerformance.begin("Storage Deletion Rebuild")
            defer { StoragePerformance.end("Storage Deletion Rebuild", id: interval) }
            return DerivedFileStateBuilder.prepare(
                files: currentFiles,
                excluding: result.deletedURLs,
                rootURL: treeRootURL
            )
        }
        let prepared = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard let prepared, !Task.isCancelled else {
            deletionState = .idle
            return
        }

        files = prepared.files
        filesRevision &+= 1
        summary = prepared.summary
        fileTree = prepared.fileTree
        largestFiles = prepared.largestFiles
        state = prepared.files.isEmpty ? .empty : .success(prepared.summary)
        skippedFileCount = 0
        persistStableState()

        if result.failedFileCount == 0 {
            deletionState = .success(deletedCount: result.deletedURLs.count)
        } else if result.deletedURLs.isEmpty {
            deletionState = .failure(.deletionFailed)
        } else {
            deletionState = .partialFailure(
                deletedCount: result.deletedURLs.count,
                failedCount: result.failedFileCount
            )
        }
    }

    /// Applies already-prepared values without running O(n) work on MainActor.
    private func applyRestoredState(_ prepared: PreparedFileState) {
        guard selectedDirectoryURL == nil else { return }
        retainSourceAccess(to: [prepared.rootURL])
        selectedDirectoryURL = prepared.rootURL
        selectedSourceURLs = [prepared.rootURL]
        selectedSourceCount = 1
        isSourceSelection = false
        selectedDirectoryName = prepared.selectedDirectoryName
        selectedDirectoryBookmark = prepared.directoryBookmark
        skippedFileCount = prepared.skippedFileCount
        files = prepared.files
        filesRevision &+= 1
        summary = prepared.summary
        fileTree = prepared.fileTree
        largestFiles = prepared.largestFiles
        if files.isEmpty {
            state = .empty
        } else if skippedFileCount > 0 {
            state = .partialFailure(prepared.summary, skippedFileCount: skippedFileCount)
        } else {
            state = .success(prepared.summary)
        }
        isRestoringStoredFiles = false
        if prepared.shouldRewriteSnapshot {
            persistStableState()
        } else if !restoredDashboardAvailable {
            persistDashboardState()
        }
        StoragePerformance.event("Storage State Published")
    }

    /// Publishes only the inexpensive dashboard state. Full file URLs and the
    /// directory tree continue restoring in the background.
    private func applyCachedDashboard(_ dashboard: StorageDashboardSnapshot) {
        guard selectedDirectoryURL == nil else { return }
        restoredDashboardAvailable = true
        selectedDirectoryName = dashboard.selectedDirectoryName
        summary = dashboard.summary
        skippedFileCount = dashboard.skippedFileCount
        if dashboard.summary.fileCount == 0 {
            state = .empty
        } else if dashboard.skippedFileCount > 0 {
            state = .partialFailure(
                dashboard.summary,
                skippedFileCount: dashboard.skippedFileCount
            )
        } else {
            state = .success(dashboard.summary)
        }
        StoragePerformance.event("Storage Dashboard Published")
    }

    /// 将稳定的单目录结果保存为仪表盘和完整快照；代次与取消机制阻止过期快照覆盖新结果。
    private func persistStableState() {
        guard let selectedDirectoryName, let selectedDirectoryBookmark else { return }
        let files = files
        let skippedFileCount = skippedFileCount
        let dashboard = summary.map {
            StorageDashboardSnapshot(
                selectedDirectoryName: selectedDirectoryName,
                summary: $0,
                skippedFileCount: skippedFileCount
            )
        }

        persistenceGeneration &+= 1
        let generation = persistenceGeneration
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            guard let self else { return }
            await self.stateStore.saveStorageDashboard(dashboard)
            guard !Task.isCancelled, generation == self.persistenceGeneration else { return }

            let worker = Task.detached(priority: .utility) {
                let interval = StoragePerformance.begin("Storage Snapshot Prepare")
                defer { StoragePerformance.end("Storage Snapshot Prepare", id: interval) }
                return FileStateSnapshot.prepare(
                    directoryBookmark: selectedDirectoryBookmark,
                    selectedDirectoryName: selectedDirectoryName,
                    files: files,
                    skippedFileCount: skippedFileCount
                )
            }
            let snapshot = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let snapshot,
                  !Task.isCancelled,
                  generation == self.persistenceGeneration else { return }
            await self.stateStore.saveFileState(snapshot)
        }
    }

    /// 仅保存已有目录名称和汇总，供下次打开时先展示轻量结果。
    private func persistDashboardState() {
        guard let selectedDirectoryName, let summary else { return }
        let dashboard = StorageDashboardSnapshot(
            selectedDirectoryName: selectedDirectoryName,
            summary: summary,
            skippedFileCount: skippedFileCount
        )
        Task { await stateStore.saveStorageDashboard(dashboard) }
    }
}
