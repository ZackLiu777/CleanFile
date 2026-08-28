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

@MainActor
/// 封装 `FileScannerViewModel` 的引用语义、状态与业务行为。
final class FileScannerViewModel: ObservableObject {
    @Published private(set) var state: ScanState = .idle
    @Published private(set) var files: [ScannedFile] = []
    @Published private(set) var summary: StorageSummary?
    @Published private(set) var fileTree: FileNode?
    @Published private(set) var largestFiles: [ScannedFile] = []
    @Published private(set) var selectedDirectoryName: String?
    @Published private(set) var deletionState: FileDeletionState = .idle

    private let scanner: MetadataFileScanner
    private var scanTask: Task<Void, Never>?
    private let deletionService = FileDeletionService()
    private let stateStore = AppStateStore.shared
    private var selectedDirectoryURL: URL?
    private var selectedDirectoryBookmark: Data?
    private var skippedFileCount = 0

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(scanner: MetadataFileScanner = MetadataFileScanner()) {
        self.scanner = scanner
        Task { [weak self] in
            guard let snapshot = await AppStateStore.shared.loadFileState() else { return }
            self?.restore(snapshot)
        }
    }

    /// 释放 ViewModel 时取消尚未结束的扫描，避免后台任务继续持有无效页面状态。
    deinit {
        scanTask?.cancel()
    }

    /// 执行 `scan` 分析流程，在遵守文件访问边界的前提下生成结果。
    func scan(directory: URL) {
        scanTask?.cancel()
        selectedDirectoryName = directory.lastPathComponent
        selectedDirectoryURL = directory
        selectedDirectoryBookmark = try? directory.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        skippedFileCount = 0
        Task { await stateStore.saveFileState(nil) }
        files = []
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
            applyDeletion(result)
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
    private func applyDeletion(_ result: FileDeletionResult) {
        files.removeAll { result.deletedURLs.contains($0.url) }
        rebuildDerivedState()

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

    /// 封装 `rebuildDerivedState` 对应的局部行为，供当前类型在统一入口下复用。
    private func rebuildDerivedState() {
        let updatedSummary = StorageSummary(files: files)
        summary = updatedSummary
        largestFiles = Array(
            files.sorted { $0.byteCount > $1.byteCount }.prefix(10)
        )
        if let selectedDirectoryURL {
            fileTree = FileTreeBuilder.build(rootURL: selectedDirectoryURL, files: files)
        }
        state = files.isEmpty ? .empty : .success(updatedSummary)
        skippedFileCount = 0
        persistStableState()
    }

    /// 加载 `restore` 所需的数据，并将结果转换为当前层可消费的状态。
    private func restore(_ snapshot: FileStateSnapshot) {
        guard case .idle = state, selectedDirectoryURL == nil else { return }
        var isStale = false
        guard let restoredRoot = try? URL(
            resolvingBookmarkData: snapshot.directoryBookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        selectedDirectoryURL = restoredRoot
        selectedDirectoryName = snapshot.selectedDirectoryName
        selectedDirectoryBookmark = isStale
            ? try? restoredRoot.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            : snapshot.directoryBookmark
        skippedFileCount = snapshot.skippedFileCount
        files = snapshot.files.compactMap { file in
            guard !file.relativePathComponents.isEmpty else { return nil }
            let restoredURL = file.relativePathComponents.reduce(restoredRoot) {
                $0.appendingPathComponent($1)
            }
            return ScannedFile(
                url: restoredURL,
                name: file.name,
                relativePathComponents: file.relativePathComponents,
                category: file.category,
                byteCount: file.byteCount,
                hasKnownByteCount: file.hasKnownByteCount,
                creationDate: file.creationDate,
                modificationDate: file.modificationDate
            )
        }

        let restoredSummary = StorageSummary(files: files)
        summary = restoredSummary
        fileTree = FileTreeBuilder.build(rootURL: restoredRoot, files: files)
        largestFiles = Array(files.sorted { $0.byteCount > $1.byteCount }.prefix(10))
        if files.isEmpty {
            state = .empty
        } else if skippedFileCount > 0 {
            state = .partialFailure(restoredSummary, skippedFileCount: skippedFileCount)
        } else {
            state = .success(restoredSummary)
        }
        if isStale { persistStableState() }
    }

    /// 持久化 `persistStableState` 对应的数据，并保持后续恢复所需的信息完整。
    private func persistStableState() {
        guard let selectedDirectoryName, let selectedDirectoryBookmark else { return }
        let snapshot = FileStateSnapshot(
            directoryBookmark: selectedDirectoryBookmark,
            selectedDirectoryName: selectedDirectoryName,
            files: files,
            skippedFileCount: skippedFileCount
        )
        Task { await stateStore.saveFileState(snapshot) }
    }
}
