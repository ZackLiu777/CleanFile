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

    private let scanner: MetadataFileScanner
    private var scanTask: Task<Void, Never>?

    init(scanner: MetadataFileScanner = MetadataFileScanner()) {
        self.scanner = scanner
    }

    deinit {
        scanTask?.cancel()
    }

    func scan(directory: URL) {
        scanTask?.cancel()
        selectedDirectoryName = directory.lastPathComponent
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
        }
    }
}
