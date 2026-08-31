import Foundation
import Dispatch
import Testing
@testable import CleanMyIPhone

@Suite("Metadata scanner edge cases")
struct MetadataFileScannerEdgeCaseTests {
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

        #expect(result.files.map(\.name) == ["visible.txt"])
        #expect(result.summary.fileCount == 1)
    }

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
        #expect(result.summary.totalBytes == 10)
        #expect(result.fileTree.byteCount == 10)
        #expect(FileTreeDiagnostics.maximumDepth(of: result.fileTree) == 3)
    }

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
        let consumer = Task<Bool, Never> {
            do {
                for try await _ in scanner.scan(directory: workspace.root) {}
                return false
            } catch {
                return true
            }
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        consumer.cancel()
        gate.open()
        let didStopWithCancellation = await consumer.value

        #expect(didStopWithCancellation)
    }

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

    private func completedResult(in events: [FileScanEvent]) -> FileScanResult? {
        events.compactMap { event in
            if case let .completed(result) = event { return result }
            return nil
        }.first
    }
}

private struct TemporaryScanWorkspace {
    let root: URL
    let fileManager: FileManager

    init() throws {
        let fileManager = FileManager.default
        self.fileManager = fileManager
        root = fileManager.temporaryDirectory
            .appending(path: "CleanMyIPhone-Scanner-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? fileManager.removeItem(at: root)
    }
}

private final class ScanGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func wait() {
        semaphore.wait()
    }

    func open() {
        semaphore.signal()
    }
}

private struct BlockingFileAccess: FileAccessProviding, Sendable {
    let gate: ScanGate

    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        gate.wait()
        return try operation()
    }
}
