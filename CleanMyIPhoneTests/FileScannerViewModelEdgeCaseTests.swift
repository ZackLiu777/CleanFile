import Foundation
import Testing
@testable import CleanMyIPhone

@MainActor
@Suite("File scanner view-model edge cases")
struct FileScannerViewModelEdgeCaseTests {
    @Test("Cancelling an idle view model is a no-op")
    func cancellingIdleStateDoesNothing() {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )

        viewModel.cancelScan()

        #expect(viewModel.state == .idle)
    }

    @Test("Selection cancellation maps to the cancelled state")
    func selectionCancellationMapsToCancelled() {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )
        let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)

        viewModel.reportSelectionFailure(error: cancellation)

        #expect(viewModel.state == .cancelled)
    }

    @Test("Selection errors map to a recoverable failure state")
    func selectionErrorMapsToFailure() {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )

        viewModel.reportSelectionFailure(error: NSError(domain: "test", code: 1))

        #expect(viewModel.state == .failure(.selectionFailed))
    }

    @Test("Empty deletion selection exposes the no-items error")
    func emptyDeletionSelectionIsReported() async {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )

        await viewModel.deleteFiles(withURLs: [])

        #expect(viewModel.deletionState == .failure(.noItemsSelected))
    }

    @Test("Deletion without a selected folder does not attempt file access")
    func deletionWithoutFolderIsReported() async {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )

        await viewModel.deleteFiles(withURLs: [URL(fileURLWithPath: "/tmp/file.txt")])

        #expect(viewModel.deletionState == .failure(.folderAccessUnavailable))
    }

    @Test("Clearing a terminal deletion result returns to idle")
    func clearDeletionResultReturnsToIdle() async {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )
        await viewModel.deleteFiles(withURLs: [])

        viewModel.clearDeletionResult()

        #expect(viewModel.deletionState == .idle)
    }

    @Test("Starting a scan immediately publishes scanning state and cancellation")
    func scanPublishesAndCanBeCancelled() async throws {
        let workspace = try ViewModelScanWorkspace()
        defer { workspace.remove() }
        try Data([1]).write(to: workspace.root.appending(path: "file.txt"))

        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess(), progressInterval: 1)
        )
        viewModel.scan(directory: workspace.root)

        #expect(viewModel.state.isScanning)
        viewModel.cancelScan()
        #expect(viewModel.state == .cancelled)
    }
}

private struct ViewModelScanWorkspace {
    let root: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appending(path: "CleanMyIPhone-ViewModel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
