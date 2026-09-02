//
//  FileScannerViewModel.swift
//  CleanMyIPhone
//

//
//  文件职责：协调 FileScanner 页面状态、用户操作与底层服务。
//  所属模块：CleanMyIPhone。
//

import Combine
import Foundation

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

nonisolated enum FileStateRestorer {
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

        let bookmark = isStale
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

nonisolated struct PreparedDerivedFileState: Sendable {
    let files: [ScannedFile]
    let summary: StorageSummary
    let fileTree: FileNode
    let largestFiles: [ScannedFile]
}

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
        let largestFiles = Array(
            retainedFiles.sorted { $0.byteCount > $1.byteCount }.prefix(10)
        )
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

@MainActor
/// 封装 `FileScannerViewModel` 的引用语义、状态与业务行为。
final class FileScannerViewModel: ObservableObject {
    @Published private(set) var state: ScanState = .idle
    @Published private(set) var files: [ScannedFile] = []
    @Published private(set) var filesRevision = 0
    @Published private(set) var summary: StorageSummary?
    @Published private(set) var fileTree: FileNode?
    @Published private(set) var largestFiles: [ScannedFile] = []
    @Published private(set) var selectedDirectoryName: String?
    @Published private(set) var deletionState: FileDeletionState = .idle
    @Published private(set) var isRestoringStoredFiles = false

    private let scanner: MetadataFileScanner
    private var scanTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var hasAttemptedRestore = false
    private let deletionService = FileDeletionService()
    private let stateStore = AppStateStore.shared
    private var selectedDirectoryURL: URL?
    private var selectedDirectoryBookmark: Data?
    private var skippedFileCount = 0
    private var restoredDashboardAvailable = false

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(scanner: MetadataFileScanner = MetadataFileScanner()) {
        self.scanner = scanner
    }

    /// 释放 ViewModel 时取消尚未结束的扫描，避免后台任务继续持有无效页面状态。
    deinit {
        scanTask?.cancel()
        restoreTask?.cancel()
        persistenceTask?.cancel()
    }

    /// Restores the previous scan only when the storage experience is opened.
    /// Decoding happens in the store actor and all O(n) reconstruction remains
    /// off MainActor; the UI receives one prepared result at the end.
    func loadIfNeeded() {
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

    /// 执行 `scan` 分析流程，在遵守文件访问边界的前提下生成结果。
    func scan(directory: URL) {
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

    /// 取消 `cancelScan` 对应的进行中任务，并收敛到可继续操作的状态。
    func cancelScan() {
        guard state.isScanning else { return }
        scanTask?.cancel()
        scanTask = nil
        state = .cancelled
    }

    /// 记录 `reportSelectionFailure` 产生的结果，并通知依赖该状态的调用方。
    func reportSelectionFailure(error: Error? = nil) {
        if let error, (error as NSError).code == NSUserCancelledError {
            state = .cancelled
        } else {
            state = .failure(.selectionFailed)
        }
    }

    /// 执行 `deleteFiles` 移除流程，并同步更新受影响的业务状态。
    func deleteFiles(withURLs selectedURLs: Set<URL>) async {
        guard !selectedURLs.isEmpty else {
            deletionState = .failure(.noItemsSelected)
            return
        }
        guard let selectedDirectoryURL else {
            deletionState = .failure(.folderAccessUnavailable)
            return
        }

        let knownFiles = files.filter { selectedURLs.contains($0.url) }
        guard knownFiles.count == selectedURLs.count else {
            deletionState = .failure(.invalidSelection)
            return
        }

        deletionState = .deleting(itemCount: knownFiles.count)
        do {
            let result = try await deletionService.delete(
                files: knownFiles,
                selectedRoot: selectedDirectoryURL
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

    /// 重置 `clearDeletionResult` 管理的状态，避免旧任务或旧数据影响下一次操作。
    func clearDeletionResult() {
        guard !deletionState.isDeleting else { return }
        deletionState = .idle
    }

    /// 处理 `handle` 输入，并根据结果推进当前业务状态。
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

    /// 更新 `applyDeletion` 对应的数据，使界面状态与底层结果保持一致。
    private func applyDeletion(_ result: FileDeletionResult) async {
        guard let selectedDirectoryURL else {
            deletionState = .failure(.folderAccessUnavailable)
            return
        }

        let currentFiles = files
        let worker = Task.detached(priority: .userInitiated) {
            let interval = StoragePerformance.begin("Storage Deletion Rebuild")
            defer { StoragePerformance.end("Storage Deletion Rebuild", id: interval) }
            return DerivedFileStateBuilder.prepare(
                files: currentFiles,
                excluding: result.deletedURLs,
                rootURL: selectedDirectoryURL
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
        selectedDirectoryURL = prepared.rootURL
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

    /// 持久化 `persistStableState` 对应的数据，并保持后续恢复所需的信息完整。
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
