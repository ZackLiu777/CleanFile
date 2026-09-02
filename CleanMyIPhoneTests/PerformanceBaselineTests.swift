import Dispatch
import Foundation
import Testing
@testable import CleanMyIPhone

/// Performance baselines intentionally report timings without enforcing a
/// device-specific deadline. CI and simulator load are too variable for a
/// stable wall-clock assertion; the correctness assertions remain mandatory.
@Suite("Performance baselines", .serialized)
struct PerformanceBaselineTests {
    @Test("Twenty-thousand file metadata aggregation remains measurable")
    func twentyThousandFileAggregation() throws {
        let root = URL(fileURLWithPath: "/performance-baseline", isDirectory: true)
        let files = (0 ..< 20_000).map { index in
            let directory = "folder-\(index % 200)"
            let name = "item-\(index).dat"
            return ScannedFile(
                url: root.appending(path: "\(directory)/\(name)"),
                name: name,
                relativePathComponents: [directory, name],
                category: FileCategory.allCases[index % FileCategory.allCases.count],
                byteCount: Int64(index + 1)
            )
        }

        let started = DispatchTime.now().uptimeNanoseconds
        var summary = StorageSummaryAccumulator()
        var tree = FileTreeAccumulator(rootURL: root)
        var largest = LargestFilesAccumulator(limit: 10)
        for file in files {
            summary.append(file)
            tree.append(file)
            largest.append(file)
        }
        let resultSummary = summary.makeSummary()
        let resultTree = tree.makeTree()
        let resultLargest = largest.sortedDescending()
        let duration = Self.milliseconds(since: started)

        print(Self.report(
            name: "storage-aggregate",
            fileCount: files.count,
            durationMilliseconds: duration
        ))

        #expect(resultSummary.fileCount == 20_000)
        #expect(resultSummary.totalBytes == 200_010_000)
        #expect(resultTree.children.count == 200)
        #expect(resultLargest.count == 10)
        #expect(resultLargest.first?.byteCount == 20_000)
    }

    @Test("Twenty-thousand real files expose metadata scan throughput")
    func twentyThousandRealFileScan() async throws {
        let fileManager = FileManager()
        let root = fileManager.temporaryDirectory
            .appending(path: "CleanFile-Performance-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }

        for directoryIndex in 0 ..< 200 {
            let directory = root.appending(path: "folder-\(directoryIndex)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
            for fileIndex in 0 ..< 100 {
                let url = directory.appending(path: "item-\(fileIndex).dat")
                guard fileManager.createFile(atPath: url.path, contents: Data([0])) else {
                    Issue.record("Unable to create performance fixture at \(url.lastPathComponent)")
                    return
                }
            }
        }

        let started = DispatchTime.now().uptimeNanoseconds
        var completed: FileScanResult?
        for try await event in MetadataFileScanner(
            fileAccess: UnrestrictedFileAccess(),
            progressInterval: 512
        ).scan(directory: root) {
            if case let .completed(result) = event {
                completed = result
            }
        }
        let duration = Self.milliseconds(since: started)
        let result = try #require(completed)

        print(Self.report(
            name: "storage-filesystem-scan",
            fileCount: result.files.count,
            durationMilliseconds: duration
        ))

        #expect(result.files.count == 20_000)
        #expect(result.summary.fileCount == 20_000)
        #expect(result.summary.totalBytes == 20_000)
        #expect(result.fileTree.children.count == 200)
        #expect(result.largestFiles.count == 10)
    }

    @Test("Twenty-thousand persisted files expose restore-stage costs")
    func twentyThousandFileRestore() throws {
        let fileManager = FileManager()
        let root = fileManager.temporaryDirectory
            .appending(path: "CleanFile-Restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        let bookmark = try root.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let files = (0 ..< 20_000).map { index in
            let directory = "folder-\(index % 200)"
            let name = "item-\(index).dat"
            return ScannedFile(
                url: root.appending(path: "\(directory)/\(name)"),
                name: name,
                relativePathComponents: [directory, name],
                category: FileCategory.allCases[index % FileCategory.allCases.count],
                byteCount: Int64(index + 1)
            )
        }
        let snapshot = try #require(FileStateSnapshot.prepare(
            directoryBookmark: bookmark,
            selectedDirectoryName: root.lastPathComponent,
            files: files,
            skippedFileCount: 0
        ))

        var started = DispatchTime.now().uptimeNanoseconds
        let encoded = try JSONEncoder().encode(snapshot)
        let encodeDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let decoded = try JSONDecoder().decode(FileStateSnapshot.self, from: encoded)
        let decodeDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let restored = try #require(FileStateRestorer.prepare(decoded))
        let reconstructionDuration = Self.milliseconds(since: started)

        print(Self.stageReport(
            name: "storage-snapshot-encode",
            fileCount: files.count,
            byteCount: encoded.count,
            durationMilliseconds: encodeDuration
        ))
        print(Self.stageReport(
            name: "storage-snapshot-decode",
            fileCount: files.count,
            byteCount: encoded.count,
            durationMilliseconds: decodeDuration
        ))
        print(Self.stageReport(
            name: "storage-state-restore",
            fileCount: files.count,
            byteCount: encoded.count,
            durationMilliseconds: reconstructionDuration
        ))

        #expect(restored.files.count == 20_000)
        #expect(restored.summary.fileCount == 20_000)
        #expect(restored.fileTree.children.count == 200)
        #expect(restored.largestFiles.count == 10)
    }

    @Test("One-million metadata records keep bounded summary aggregation")
    func oneMillionMetadataAggregation() {
        let root = URL(fileURLWithPath: "/million-record-baseline", isDirectory: true)
        var summary = StorageSummaryAccumulator()
        var largest = LargestFilesAccumulator(limit: 10)
        let started = DispatchTime.now().uptimeNanoseconds

        for index in 0 ..< 1_000_000 {
            let name = "item-\(index).dat"
            let file = ScannedFile(
                url: root.appending(path: name),
                name: name,
                relativePathComponents: [name],
                category: FileCategory.allCases[index % FileCategory.allCases.count],
                byteCount: Int64(index + 1)
            )
            summary.append(file)
            largest.append(file)
        }

        let resultSummary = summary.makeSummary()
        let resultLargest = largest.sortedDescending()
        let duration = Self.milliseconds(since: started)
        print(Self.report(
            name: "storage-million-bounded-aggregate",
            fileCount: 1_000_000,
            durationMilliseconds: duration
        ))

        #expect(resultSummary.fileCount == 1_000_000)
        #expect(resultSummary.totalBytes == 500_000_500_000)
        #expect(resultLargest.count == 10)
        #expect(resultLargest.first?.byteCount == 1_000_000)
    }

    private static func milliseconds(since started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    private static func report(
        name: String,
        fileCount: Int,
        durationMilliseconds: Double
    ) -> String {
        let seconds = durationMilliseconds / 1_000
        let throughput = seconds > 0 ? Double(fileCount) / seconds : 0
        return String(
            format: "PERF_BASELINE %@ files=%d duration_ms=%.2f files_per_second=%.0f",
            name,
            fileCount,
            durationMilliseconds,
            throughput
        )
    }

    private static func stageReport(
        name: String,
        fileCount: Int,
        byteCount: Int,
        durationMilliseconds: Double
    ) -> String {
        String(
            format: "PERF_BASELINE %@ files=%d snapshot_bytes=%d duration_ms=%.2f",
            name,
            fileCount,
            byteCount,
            durationMilliseconds
        )
    }
}
