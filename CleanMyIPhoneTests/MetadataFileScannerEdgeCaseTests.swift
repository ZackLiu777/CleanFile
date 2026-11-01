// 元数据扫描器的边界与取消行为测试。
//
// 用例在隔离的临时目录中构造别名、嵌套目录、隐藏文件与混合选择，
// 检查扫描事件、相对路径、汇总信息及错误传播。取消用例通过可控的
// 文件访问替身同步工作任务，验证消费者取消能传递到扫描工作任务。
// 每个工作目录在用例结束时清理，不需要访问真实用户数据。

import Foundation
import Dispatch
import Testing
@testable import CleanMyIPhone

/// 验证扫描结果对边界输入和异步生命周期保持一致的语义。
@Suite("Metadata scanner edge cases")
struct MetadataFileScannerEdgeCaseTests {
    /// 通过别名选择目录时，结果 URL 仍使用用户选择的路径空间。
    @Test("Scanning through a directory alias keeps deletion URLs under the selected root")
    func selectedRootNamespaceIsPreserved() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        let actual = workspace.root.appendingPathComponent("Actual", isDirectory: true)
        let selected = workspace.root.appendingPathComponent("Selected", isDirectory: true)
        try workspace.fileManager.createDirectory(at: actual, withIntermediateDirectories: true)
        try Data([1]).write(to: actual.appendingPathComponent("item.txt"))
        try workspace.fileManager.createSymbolicLink(at: selected, withDestinationURL: actual)

        let events = try await collectEvents(
            from: MetadataFileScanner(fileAccess: UnrestrictedFileAccess()),
            directory: selected
        )
        let result = try #require(completedResult(in: events))
        let file = try #require(result.files.first)
        #expect(file.url == selected.appendingPathComponent("item.txt"))
        #expect(file.relativePathComponents == ["item.txt"])
    }

    /// 混合来源扫描保留别名路径，并以来源名称作为虚拟树的前缀。
    @Test("Mixed-source scanning recognizes a selected directory alias and preserves nested URLs")
    func selectedDirectoryAliasInMixedSources() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        let actual = workspace.root.appendingPathComponent("Actual", isDirectory: true)
        let nested = actual.appendingPathComponent("Nested", isDirectory: true)
        let selected = workspace.root.appendingPathComponent("Selected", isDirectory: true)
        try workspace.fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([1, 2]).write(to: nested.appendingPathComponent("item.txt"))
        try workspace.fileManager.createSymbolicLink(at: selected, withDestinationURL: actual)
        var events: [FileScanEvent] = []
        let scanner = MetadataFileScanner(fileAccess: UnrestrictedFileAccess())
        for try await event in scanner.scan(sources: [selected]) { events.append(event) }
        let result = try #require(completedResult(in: events))
        #expect(result.files.count == 1)
        let file = try #require(result.files.first)
        #expect(file.url == selected.appendingPathComponent("Nested/item.txt"))
        // scan(sources:) prefixes each source in its virtual aggregate tree.
        #expect(file.relativePathComponents == ["Selected", "Nested", "item.txt"])
        #expect(result.summary.totalBytes == 2)
        #expect(result.failures.isEmpty)
    }

    /// 空目录是成功结果，仍应产生进度并返回零文件汇总。
    @Test("Scanning an empty directory emits a completed zero-file result")
    func emptyDirectoryCompletesWithZeroFiles() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }

        let events = try await collectEvents(
            from: MetadataFileScanner(fileAccess: UnrestrictedFileAccess(), progressInterval: 1),
            directory: workspace.root
        )
        let result = try #require(completedResult(in: events))

        #expect(result.files.isEmpty)
        #expect(result.failures.isEmpty)
        #expect(result.summary.fileCount == 0)
        #expect(result.fileTree.children.isEmpty)
        #expect(events.contains { if case .progress = $0 { true } else { false } })
    }

    /// 隐藏文件及隐藏目录内容被排除，可见文件仍被统计。
    @Test("Hidden files are excluded while visible files remain scannable")
    func hiddenFilesAreSkipped() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        try Data(repeating: 1, count: 3).write(to: workspace.root.appending(path: "visible.txt"))
        try Data(repeating: 2, count: 7).write(to: workspace.root.appending(path: ".hidden.txt"))
        try workspace.fileManager.createDirectory(
            at: workspace.root.appending(path: ".hidden-folder", directoryHint: .isDirectory),
            withIntermediateDirectories: false
        )
        try Data([3]).write(to: workspace.root.appending(path: ".hidden-folder/inside.txt"))

        let events = try await collectEvents(
            from: MetadataFileScanner(fileAccess: UnrestrictedFileAccess(), progressInterval: 1),
            directory: workspace.root
        )
        let result = try #require(completedResult(in: events))

        #expect(result.files.map { $0.name } == ["visible.txt"])
        #expect(result.summary.fileCount == 1)
    }

    /// 嵌套路径保留非英文名称，文件树与摘要汇总相同字节数。
    @Test("Nested directories preserve relative paths and aggregate sizes")
    func nestedDirectoriesAggregateMetadata() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        let nested = workspace.root.appending(path: "资料/Project Files", directoryHint: .isDirectory)
        try workspace.fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 10).write(to: nested.appending(path: "报告.pdf"))

        let events = try await collectEvents(
            from: MetadataFileScanner(fileAccess: UnrestrictedFileAccess(), progressInterval: 1),
            directory: workspace.root
        )
        let result = try #require(completedResult(in: events))
        let file = try #require(result.files.first)

        #expect(file.relativePathComponents == ["资料", "Project Files", "报告.pdf"])
        #expect(file.url == nested.appendingPathComponent("报告.pdf"))
        #expect(result.summary.totalBytes == 10)
        #expect(result.fileTree.byteCount == 10)
        #expect(FileTreeDiagnostics.maximumDepth(of: result.fileTree) == 3)
    }

    /// 文件和包含它的目录同时被选中时，文件不应重复计数。
    @Test("Multiple selected files and folders produce one de-duplicated result")
    func mixedSourcesAreCombinedWithoutDuplicates() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        let folder = workspace.root.appending(path: "Folder", directoryHint: .isDirectory)
        try workspace.fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        let nestedFile = folder.appending(path: "inside.pdf")
        let standaloneFile = workspace.root.appending(path: "photo.jpg")
        try Data(repeating: 1, count: 7).write(to: nestedFile)
        try Data(repeating: 2, count: 11).write(to: standaloneFile)

        let scanner = MetadataFileScanner(
            fileAccess: UnrestrictedFileAccess(),
            progressInterval: 1
        )
        var events: [FileScanEvent] = []
        for try await event in scanner.scan(sources: [folder, nestedFile, standaloneFile]) {
            events.append(event)
        }
        let result = try #require(completedResult(in: events))

        #expect(result.files.count == 2)
        #expect(result.summary.totalBytes == 18)
        #expect(Set(result.files.map(\.url)) == [nestedFile, standaloneFile])
        #expect(result.fileTree.children.count == 2)
    }

    /// 单目录入口收到普通文件时应报告具体类型错误。
    @Test("A non-directory selection fails with the explicit not-directory error")
    func nonDirectorySelectionFailsClearly() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        let fileURL = workspace.root.appending(path: "selected.txt")
        try Data([1]).write(to: fileURL)

        var receivedError: Error?
        do {
            for try await _ in MetadataFileScanner(fileAccess: UnrestrictedFileAccess()).scan(directory: fileURL) {}
        } catch {
            receivedError = error
        }

        #expect((receivedError as? FileScanError) == .notDirectory)
    }

    /// 目录消失应暴露为失败，不能伪装成空目录或取消。
    @Test("Missing directory failures are surfaced instead of producing an empty success")
    func missingDirectoryDoesNotLookEmpty() async throws {
        let workspace = try TemporaryScanWorkspace()
        let missing = workspace.root.appending(path: "gone", directoryHint: .isDirectory)
        workspace.remove()

        var receivedError: Error?
        do {
            for try await _ in MetadataFileScanner(fileAccess: UnrestrictedFileAccess()).scan(directory: missing) {}
        } catch {
            receivedError = error
        }

        #expect(receivedError != nil)
        if let scanError = receivedError as? FileScanError {
            #expect(scanError != .cancelled)
        }
    }

    /// 非法进度间隔仍能安全处理，最终进度覆盖所有扫描项。
    @Test("Progress interval is normalized and final progress includes every file")
    func progressIntervalAndFinalProgressAreSafe() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        for index in 0 ..< 5 {
            try Data(repeating: UInt8(index), count: index + 1)
                .write(to: workspace.root.appending(path: "file-\(index).bin"))
        }

        let events = try await collectEvents(
            from: MetadataFileScanner(fileAccess: UnrestrictedFileAccess(), progressInterval: 0),
            directory: workspace.root
        )
        let progress = events.compactMap { event -> ScanProgress? in
            if case let .progress(value) = event { return value }
            return nil
        }
        let final = try #require(progress.last)

        #expect(final.scannedFileCount == 5)
        #expect(final.scannedByteCount == 15)
        #expect(progress.first?.scannedFileCount == 0)
    }

    /// 最大文件列表有数量上限，但总计仍包含整个扫描结果。
    @Test("Largest-file output is bounded while summary still includes the full scan")
    func largeInputKeepsBoundedLargestFiles() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        for index in 0 ..< 25 {
            try Data(repeating: UInt8(index), count: index + 1)
                .write(to: workspace.root.appending(path: "item-\(index).bin"))
        }

        let events = try await collectEvents(
            from: MetadataFileScanner(fileAccess: UnrestrictedFileAccess(), progressInterval: 100),
            directory: workspace.root
        )
        let result = try #require(completedResult(in: events))

        #expect(result.files.count == 25)
        #expect(result.summary.fileCount == 25)
        #expect(result.largestFiles.count == 10)
        #expect(result.largestFiles.first?.byteCount == 25)
        #expect(result.largestFiles.last?.byteCount == 16)
    }

    /// 使用门闩确保工作任务已经进入访问阶段，再检查取消是否传递。
    @Test("Cancelling a consumer cancels the detached scan worker")
    func cancellingConsumerStopsScan() async throws {
        let workspace = try TemporaryScanWorkspace()
        defer { workspace.remove() }
        try Data([1]).write(to: workspace.root.appending(path: "file.txt"))
        let gate = ScanGate()
        let scanner = MetadataFileScanner(
            fileAccess: BlockingFileAccess(gate: gate),
            progressInterval: 1
        )
        let consumer = Task<Void, Never> {
            do {
                for try await _ in scanner.scan(directory: workspace.root) {}
            } catch {
                // The assertion below verifies worker cancellation directly.
            }
        }

        let workerDidEnter = await gate.waitUntilWorkerEntered()
        #expect(workerDidEnter)
        consumer.cancel()
        let workerObservedCancellation = await gate.waitForWorkerCancellation()
        // Always release the test double so a failed cancellation assertion
        // cannot leave its detached worker blocked after the test returns.
        gate.open()
        _ = await consumer.value

        #expect(workerObservedCancellation)
    }

    /// 收集单目录扫描的完整事件序列，供用例检查进度和最终结果。
    private func collectEvents(
        from scanner: MetadataFileScanner,
        directory: URL
    ) async throws -> [FileScanEvent] {
        var events: [FileScanEvent] = []
        for try await event in scanner.scan(directory: directory) {
            events.append(event)
        }
        return events
    }

    /// 从事件序列中提取首次完成结果；缺失时由调用方断言失败。
    private func completedResult(in events: [FileScanEvent]) -> FileScanResult? {
        events.compactMap { event in
            if case let .completed(result) = event { return result }
            return nil
        }.first
    }
}

/// 为单个用例创建隔离目录，避免测试操作影响其他文件。
private struct TemporaryScanWorkspace {
    let root: URL
    let fileManager: FileManager

    /// 创建唯一的临时扫描目录，供边界用例隔离文件系统状态。
    init() throws {
        let fileManager = FileManager.default
        self.fileManager = fileManager
        root = fileManager.temporaryDirectory
            .appending(path: "CleanMyIPhone-Scanner-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 尽力清理临时目录，避免清理错误掩盖原有断言结果。
    func remove() {
        try? fileManager.removeItem(at: root)
    }
}

/// 使用锁保护共享状态的测试门闩，用于观察工作任务是否收到取消。
/// 等待方法设有期限，且用例会显式释放门闩，防止失败时遗留阻塞任务。
private final class ScanGate: @unchecked Sendable {
    private let lock = NSLock()
    private var workerEntered = false
    private var releaseRequested = false
    private var workerFinished = false
    private var workerObservedCancellation = false

    /// 阻塞替身访问，直到收到任务取消或测试主动释放门闩。
    func wait() throws {
        updateState { $0.workerEntered = true }

        while !Task.isCancelled, !state.releaseRequested {
            Thread.sleep(forTimeInterval: 0.001)
        }

        updateState {
            $0.workerFinished = true
            $0.workerObservedCancellation = Task.isCancelled
        }
        try Task.checkCancellation()
    }

    /// 释放阻塞中的工作任务，供测试清理使用。
    func open() {
        updateState { $0.releaseRequested = true }
    }

    /// 等待工作任务进入门闩，超时则返回当前观测结果。
    func waitUntilWorkerEntered() async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if state.workerEntered { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return state.workerEntered
    }

    /// 等待工作任务退出并报告其是否观察到了取消。
    func waitForWorkerCancellation() async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let snapshot = state
            if snapshot.workerFinished {
                return snapshot.workerObservedCancellation
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let snapshot = state
        return snapshot.workerFinished && snapshot.workerObservedCancellation
    }

    private var state: State {
        lock.lock()
        defer { lock.unlock() }
        return State(
            workerEntered: workerEntered,
            releaseRequested: releaseRequested,
            workerFinished: workerFinished,
            workerObservedCancellation: workerObservedCancellation
        )
    }

    /// 在同一把锁下修改状态快照并写回，避免跨线程读写竞争。
    private func updateState(_ update: (inout State) -> Void) {
        lock.lock()
        var value = State(
            workerEntered: workerEntered,
            releaseRequested: releaseRequested,
            workerFinished: workerFinished,
            workerObservedCancellation: workerObservedCancellation
        )
        update(&value)
        workerEntered = value.workerEntered
        releaseRequested = value.releaseRequested
        workerFinished = value.workerFinished
        workerObservedCancellation = value.workerObservedCancellation
        lock.unlock()
    }

    /// 门闩的完整状态快照，只在持锁读写或值复制后使用。
    private struct State {
        var workerEntered: Bool
        var releaseRequested: Bool
        var workerFinished: Bool
        var workerObservedCancellation: Bool
    }
}

/// 在执行实际访问闭包前进入门闩，供取消传播用例控制时序。
private struct BlockingFileAccess: FileAccessProviding, Sendable {
    let gate: ScanGate

    /// 等待门闩放行；如已取消，直接传播取消错误而不执行闭包。
    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        try gate.wait()
        return try operation()
    }
}
