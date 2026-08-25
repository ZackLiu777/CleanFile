//
//  FileScannerViewModel.swift
//  CleanMyIPhone
//

import Combine
import Foundation

@MainActor
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

    init(scanner: MetadataFileScanner = MetadataFileScanner()) {
        self.scanner = scanner
        Task { [weak self] in
            guard let snapshot = await AppStateStore.shared.loadFileState() else { return }
            self?.restore(snapshot)
        }
    }

    deinit {
        scanTask?.cancel()
    }

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

    func cancelScan() {
        guard state.isScanning else { return }
        scanTask?.cancel()
        scanTask = nil
        state = .cancelled
    }

    func reportSelectionFailure(error: Error? = nil) {
        if let error, (error as NSError).code == NSUserCancelledError {
            state = .cancelled
        } else {
            state = .failure(.selectionFailed)
        }
    }

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

    func clearDeletionResult() {
        guard !deletionState.isDeleting else { return }
        deletionState = .idle
    }

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
