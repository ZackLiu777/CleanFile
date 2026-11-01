// 文件删除的安全边界测试。
//
// 用例覆盖目录别名、逃离所选根目录的符号链接、空选择和无效目标，
// 以及成功与部分失败的结果表示。涉及真实文件系统的检查只使用独立
// 临时目录，并在用例结束时清理；其他验证不需要删除实际文件。

import Foundation
import Testing
@testable import CleanMyIPhone

/// 确保删除目标受所选目录约束，且结果能够表达部分成功。
@Suite("File deletion safety boundaries")
struct FileDeletionEdgeCaseTests {
    /// 别名和真实目录应视为同一边界，但指向目录外部的链接不能通过校验。
    /// 根目录本身也不是可删除的子项，避免误删整个选择范围。
    @Test("Directory aliases match, but links escaping the root remain rejected")
    func canonicalDirectoryBoundaries() throws {
        let manager = FileManager.default
        let workspace = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: workspace) }
        let root = workspace.appendingPathComponent("Root", isDirectory: true)
        let alias = workspace.appendingPathComponent("Alias", isDirectory: true)
        let outside = workspace.appendingPathComponent("Outside", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: alias, withDestinationURL: root)
        try Data([1]).write(to: root.appendingPathComponent("inside.txt"))
        try Data([2]).write(to: outside.appendingPathComponent("outside.txt"))
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("Escape"), withDestinationURL: outside
        )
        #expect(FileDeletionService.contains(root.appendingPathComponent("inside.txt"), root: alias))
        #expect(FileDeletionService.contains(alias.appendingPathComponent("inside.txt"), root: root))
        #expect(!FileDeletionService.contains(root.appendingPathComponent("Escape/outside.txt"), root: root))
        #expect(!FileDeletionService.contains(root, root: alias))
        #expect(!FileDeletionService.contains(alias, root: root))
        #expect(!FileDeletionService.contains(alias, root: alias))
    }

    /// 空选择应在访问文件系统前返回明确错误。
    @Test("Deleting an empty selection is rejected before touching the file system")
    func emptySelectionIsRejected() async {
        let service = FileDeletionService()
        var receivedError: Error?

        do {
            _ = try await service.delete(
                files: [],
                selectedRoot: URL(fileURLWithPath: "/tmp/clean-file-root", isDirectory: true)
            )
        } catch {
            receivedError = error
        }

        #expect((receivedError as? FileDeletionError) == .noItemsSelected)
    }

    /// 名称有共同前缀的相邻目录并不属于所选根目录。
    @Test("A selection outside the analyzed folder is rejected atomically")
    func outsideSelectionIsRejected() async {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let outside = ScannedFile(
            url: URL(fileURLWithPath: "/tmp/RootBackup/important.txt"),
            name: "important.txt",
            relativePathComponents: ["important.txt"],
            category: .document,
            byteCount: 1
        )
        let service = FileDeletionService()
        var receivedError: Error?

        do {
            _ = try await service.delete(files: [outside], selectedRoot: root)
        } catch {
            receivedError = error
        }

        #expect((receivedError as? FileDeletionError) == .invalidSelection)
    }

    /// 防止将根目录自身当作扫描出的普通文件删除。
    @Test("Selection validation rejects the root folder itself")
    func rootItselfCannotBeDeleted() async {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let rootItem = ScannedFile(
            url: root,
            name: "Root",
            relativePathComponents: [],
            category: .other,
            byteCount: 0
        )
        let service = FileDeletionService()
        var receivedError: Error?

        do {
            _ = try await service.delete(files: [rootItem], selectedRoot: root)
        } catch {
            receivedError = error
        }

        #expect((receivedError as? FileDeletionError) == .invalidSelection)
    }

    /// 上层需要同时保留已删除 URL 和失败数量，以正确更新部分成功的状态。
    @Test("Deletion result can represent complete and partial outcomes")
    func deletionResultRepresentsOutcomeShape() {
        let first = URL(fileURLWithPath: "/tmp/Root/first.txt")
        let second = URL(fileURLWithPath: "/tmp/Root/second.txt")
        let complete = FileDeletionResult(deletedURLs: [first, second], failedFileCount: 0)
        let partial = FileDeletionResult(deletedURLs: [first], failedFileCount: 1)

        #expect(complete.deletedURLs.count == 2)
        #expect(complete.failedFileCount == 0)
        #expect(partial.deletedURLs == [first])
        #expect(partial.failedFileCount == 1)
    }

    /// 空闲和各种终态均不应继续显示删除进行中。
    @Test("Deletion state activity is false for all terminal and idle states")
    func deletionStateTerminalStatesAreInactive() {
        let states: [FileDeletionState] = [
            .idle,
            .success(deletedCount: 0),
            .partialFailure(deletedCount: 0, failedCount: 2),
            .failure(.deletionFailed)
        ]

        #expect(states.allSatisfy { !$0.isDeleting })
    }
}
