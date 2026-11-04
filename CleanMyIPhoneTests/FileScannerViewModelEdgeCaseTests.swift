//
//  文件扫描状态边界
//
//  覆盖扫描视图模型的取消、选取错误和删除前置条件。
//  通过临时工作区检查状态转换，避免把空选择误当作文件操作。
//  区分用户取消和普通选择失败，并检查没有授权来源时不会启动删除。
//  需要扫描时只在独立临时目录创建测试文件，任务结束后清理目录。
//

import Foundation
import Testing
@testable import CleanMyIPhone

/// 验证选取失败、取消和删除前置条件的状态转换。
@MainActor
@Suite("File scanner view-model edge cases")
struct FileScannerViewModelEdgeCaseTests {
    /// 验证未开始扫描时取消不会把空闲状态误改为取消状态。
    @Test("Cancelling an idle view model is a no-op")
    func cancellingIdleStateDoesNothing() {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )

        viewModel.cancelScan()

        #expect(viewModel.state == .idle)
    }

    /// 将系统文件选择取消错误映射为取消状态，而非普通失败。
    @Test("Selection cancellation maps to the cancelled state")
    func selectionCancellationMapsToCancelled() {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )
        let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)

        viewModel.reportSelectionFailure(error: cancellation)

        #expect(viewModel.state == .cancelled)
    }

    /// 非取消的选择错误应映射为可处理的选择失败状态。
    @Test("Selection errors map to a recoverable failure state")
    func selectionErrorMapsToFailure() {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )

        viewModel.reportSelectionFailure(error: NSError(domain: "test", code: 1))

        #expect(viewModel.state == .failure(.selectionFailed))
    }

    /// 空删除选择应直接显示错误，不进入实际删除流程。
    @Test("Empty deletion selection exposes the no-items error")
    func emptyDeletionSelectionIsReported() async {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )

        await viewModel.deleteFiles(withURLs: [])

        #expect(viewModel.deletionState == .failure(.noItemsSelected))
    }

    /// 没有选定目录时不尝试访问或删除文件。
    @Test("Deletion without a selected folder does not attempt file access")
    func deletionWithoutFolderIsReported() async {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )

        await viewModel.deleteFiles(withURLs: [URL(fileURLWithPath: "/tmp/file.txt")])

        #expect(viewModel.deletionState == .failure(.folderAccessUnavailable))
    }

    /// 先制造空选择删除错误，再确认清除结果后恢复空闲状态。
    @Test("Clearing a terminal deletion result returns to idle")
    func clearDeletionResultReturnsToIdle() async {
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )
        await viewModel.deleteFiles(withURLs: [])

        viewModel.clearDeletionResult()

        #expect(viewModel.deletionState == .idle)
    }

    /// 检查扫描开始后立即暴露进行中状态，并能响应取消。
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
    @Test("Deleting a scanned file preserves the skipped-source warning")
    func deletionPreservesPartialScanWarning() async throws {
        let workspace = try ViewModelScanWorkspace()
        defer { workspace.remove() }
        let existing = workspace.root.appending(path: "existing.txt")
        let missing = workspace.root.appending(path: "missing.txt")
        try Data([1]).write(to: existing)
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )
        viewModel.scan(sources: [existing, missing])
        try await waitUntilScanFinishes(viewModel)
        guard case .partialFailure(_, let skippedBefore) = viewModel.state else {
            Issue.record("Expected a partial scan result")
            return
        }
        #expect(skippedBefore == 1)

        await viewModel.deleteFiles(withURLs: [existing])

        guard case .partialFailure(let summary, let skippedAfter) = viewModel.state else {
            Issue.record("Expected the skipped-source warning after deletion")
            return
        }
        #expect(skippedAfter == 1)
        #expect(summary.fileCount == 0)
        #expect(viewModel.deletionState == .success(deletedCount: 1))
    }

    @Test("Changing the source is rejected while deletion is active")
    func cannotChangeSourceWhileDeleting() async throws {
        let workspace = try ViewModelScanWorkspace()
        defer { workspace.remove() }
        let file = workspace.root.appending(path: "file.txt")
        try Data([1]).write(to: file)
        let viewModel = FileScannerViewModel(
            scanner: MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        )
        viewModel.scan(directory: workspace.root)
        try await waitUntilScanFinishes(viewModel)

        let deletion = Task { await viewModel.deleteFiles(withURLs: [file]) }
        for _ in 0..<100 where !viewModel.deletionState.isDeleting {
            await Task.yield()
        }
        guard viewModel.deletionState.isDeleting else {
            Issue.record("Deletion did not enter its active state")
            await deletion.value
            return
        }
        let revision = viewModel.filesRevision
        viewModel.scan(directory: workspace.root.appending(path: "another", directoryHint: .isDirectory))
        viewModel.scan(sources: [workspace.root])
        #expect(viewModel.filesRevision == revision)
        #expect(viewModel.selectedDirectoryName == workspace.root.lastPathComponent)
        await deletion.value
    }

    private func waitUntilScanFinishes(_ viewModel: FileScannerViewModel) async throws {
        for _ in 0..<500 {
            if !viewModel.state.isScanning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Scan did not finish")
    }

}

/// 为视图模型测试创建并清理独立的临时工作区。
private struct ViewModelScanWorkspace {
    let root: URL

    /// 在系统临时目录创建唯一根目录，避免测试互相影响或访问用户文件。
    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appending(path: "CleanMyIPhone-ViewModel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 尽力删除测试根目录及其中创建的文件。
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
