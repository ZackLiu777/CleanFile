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

    @Test("One-hundred-thousand persisted files expose snapshot scaling")
    func oneHundredThousandFileSnapshotScaling() throws {
        let fileManager = FileManager()
        let root = fileManager.temporaryDirectory
            .appending(path: "CleanFile-Large-Restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        let bookmark = try root.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let files = (0 ..< 100_000).map { index in
            let directory = "folder-\(index % 1_000)"
            let name = "item-\(index).dat"
            return ScannedFile(
                url: root.appending(path: "\(directory)/\(name)"),
                name: name,
                relativePathComponents: [directory, name],
                category: FileCategory.allCases[index % FileCategory.allCases.count],
                byteCount: Int64(index + 1)
            )
        }

        var started = DispatchTime.now().uptimeNanoseconds
        let snapshot = try #require(FileStateSnapshot.prepare(
            directoryBookmark: bookmark,
            selectedDirectoryName: root.lastPathComponent,
            files: files,
            skippedFileCount: 0
        ))
        let prepareDuration = Self.milliseconds(since: started)

        let legacySnapshot = LegacyPerformanceFileStateSnapshot(
            directoryBookmark: bookmark,
            selectedDirectoryName: root.lastPathComponent,
            files: files.map(LegacyPerformancePersistedFile.init),
            skippedFileCount: 0
        )
        started = DispatchTime.now().uptimeNanoseconds
        let legacyEncoded = try JSONEncoder().encode(legacySnapshot)
        let legacyEncodeDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let encoded = try JSONEncoder().encode(snapshot)
        let encodeDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let legacyDecoded = try JSONDecoder().decode(FileStateSnapshot.self, from: legacyEncoded)
        let legacyDecodeDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let decoded = try JSONDecoder().decode(FileStateSnapshot.self, from: encoded)
        let decodeDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let restored = try #require(FileStateRestorer.prepare(decoded))
        let restoreDuration = Self.milliseconds(since: started)

        print(String(
            format: "PERF_BASELINE storage-large-snapshot files=%d snapshot_bytes=%d prepare_ms=%.2f encode_ms=%.2f decode_ms=%.2f restore_ms=%.2f",
            files.count,
            encoded.count,
            prepareDuration,
            encodeDuration,
            decodeDuration,
            restoreDuration
        ))
        let sizeImprovement = Double(legacyEncoded.count - encoded.count)
            / Double(legacyEncoded.count) * 100
        let encodeImprovement = (legacyEncodeDuration - encodeDuration)
            / legacyEncodeDuration * 100
        let decodeImprovement = (legacyDecodeDuration - decodeDuration)
            / legacyDecodeDuration * 100
        print(String(
            format: "PERF_COMPARISON storage-compact-snapshot files=%d legacy_bytes=%d compact_bytes=%d size_improvement_percent=%.1f legacy_encode_ms=%.2f compact_encode_ms=%.2f encode_improvement_percent=%.1f legacy_decode_ms=%.2f compact_decode_ms=%.2f decode_improvement_percent=%.1f",
            files.count,
            legacyEncoded.count,
            encoded.count,
            sizeImprovement,
            legacyEncodeDuration,
            encodeDuration,
            encodeImprovement,
            legacyDecodeDuration,
            decodeDuration,
            decodeImprovement
        ))

        #expect(restored.files.count == files.count)
        #expect(restored.summary.fileCount == files.count)
        #expect(restored.fileTree.children.count == 1_000)
        #expect(restored.largestFiles.count == 10)
        #expect(legacyDecoded.files == decoded.files)
    }

    @Test("Rejected chunked persistence experiment compares buffer and codec costs")
    func chunkedPersistenceComparison() throws {
        // This remains as evidence only. Production reverted to the compact
        // monolithic snapshot after real-device scans became slower and hotter.
        let root = URL(fileURLWithPath: "/chunked-persistence", isDirectory: true)
        let files = (0 ..< 100_000).map { index in
            let directory = "folder-\(index % 1_000)"
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
            directoryBookmark: Data([1, 2, 3]),
            selectedDirectoryName: "chunked-persistence",
            files: files,
            skippedFileCount: 0
        ))
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        var started = DispatchTime.now().uptimeNanoseconds
        let monolithicData = try encoder.encode(snapshot)
        let monolithicEncodeDuration = Self.milliseconds(since: started)
        started = DispatchTime.now().uptimeNanoseconds
        let monolithicDecoded = try decoder.decode(FileStateSnapshot.self, from: monolithicData)
        let monolithicDecodeDuration = Self.milliseconds(since: started)

        let chunkSize = 10_000
        var chunkData: [Data] = []
        chunkData.reserveCapacity((snapshot.files.count + chunkSize - 1) / chunkSize)
        started = DispatchTime.now().uptimeNanoseconds
        var chunkStart = 0
        while chunkStart < snapshot.files.count {
            let chunkEnd = min(chunkStart + chunkSize, snapshot.files.count)
            chunkData.append(try encoder.encode(Array(snapshot.files[chunkStart ..< chunkEnd])))
            chunkStart = chunkEnd
        }
        let chunkedEncodeDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        var chunkedDecodedFiles: [PersistedScannedFile] = []
        chunkedDecodedFiles.reserveCapacity(snapshot.files.count)
        for data in chunkData {
            chunkedDecodedFiles.append(contentsOf: try decoder.decode(
                [PersistedScannedFile].self,
                from: data
            ))
        }
        let chunkedDecodeDuration = Self.milliseconds(since: started)
        let chunkedByteCount = chunkData.reduce(0) { $0 + $1.count }
        let maximumChunkByteCount = chunkData.map(\.count).max() ?? 0
        let peakBufferImprovement = Double(monolithicData.count - maximumChunkByteCount)
            / Double(monolithicData.count) * 100
        let encodeChange = (monolithicEncodeDuration - chunkedEncodeDuration)
            / monolithicEncodeDuration * 100
        let decodeChange = (monolithicDecodeDuration - chunkedDecodeDuration)
            / monolithicDecodeDuration * 100

        print(String(
            format: "PERF_COMPARISON storage-chunked-persistence files=%d chunks=%d monolithic_bytes=%d chunked_total_bytes=%d maximum_chunk_bytes=%d peak_buffer_improvement_percent=%.1f monolithic_encode_ms=%.2f chunked_encode_ms=%.2f encode_improvement_percent=%.1f monolithic_decode_ms=%.2f chunked_decode_ms=%.2f decode_improvement_percent=%.1f",
            files.count,
            chunkData.count,
            monolithicData.count,
            chunkedByteCount,
            maximumChunkByteCount,
            peakBufferImprovement,
            monolithicEncodeDuration,
            chunkedEncodeDuration,
            encodeChange,
            monolithicDecodeDuration,
            chunkedDecodeDuration,
            decodeChange
        ))

        #expect(chunkedDecodedFiles == monolithicDecoded.files)
        #expect(chunkData.count == 10)
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

    @Test("Deletion rebuild compares foreground baseline and background preparation paths")
    func deletionRebuildComparison() throws {
        let root = URL(fileURLWithPath: "/deletion-comparison", isDirectory: true)
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
        let deletedURLs = Set(files.enumerated().compactMap { index, file in
            index.isMultiple(of: 5) ? file.url : nil
        })

        var started = DispatchTime.now().uptimeNanoseconds
        let legacyFiles = files.filter { !deletedURLs.contains($0.url) }
        let legacySummary = StorageSummary(files: legacyFiles)
        let legacyLargest = Array(
            legacyFiles.sorted { $0.byteCount > $1.byteCount }.prefix(10)
        )
        let legacyTree = FileTreeBuilder.build(rootURL: root, files: legacyFiles)
        let legacyDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let optimized = try #require(DerivedFileStateBuilder.prepare(
            files: files,
            excluding: deletedURLs,
            rootURL: root
        ))
        let optimizedDuration = Self.milliseconds(since: started)
        let improvement = legacyDuration > 0
            ? (legacyDuration - optimizedDuration) / legacyDuration * 100
            : 0

        print(String(
            format: "PERF_COMPARISON storage-deletion-rebuild files=%d baseline_ms=%.2f optimized_ms=%.2f improvement_percent=%.1f",
            files.count,
            legacyDuration,
            optimizedDuration,
            improvement
        ))

        #expect(optimized.files == legacyFiles)
        #expect(optimized.summary == legacySummary)
        #expect(optimized.largestFiles == legacyLargest)
        #expect(optimized.fileTree == legacyTree)
    }

    @Test("File selection compares repeated body sorting and cached display order")
    func fileSelectionDisplayOrderComparison() {
        let root = URL(fileURLWithPath: "/file-list-comparison", isDirectory: true)
        let files = (0 ..< 20_000).map { index in
            let name = "item-\(index).dat"
            return ScannedFile(
                url: root.appending(path: name),
                name: name,
                relativePathComponents: [name],
                category: .other,
                byteCount: Int64((index * 7_919) % 20_000)
            )
        }
        let interactionCount = 50

        var baselineSelection = Set<URL>()
        var baselineChecksum: Int64 = 0
        var started = DispatchTime.now().uptimeNanoseconds
        for interaction in 0 ..< interactionCount {
            let displayedFiles = FileDisplayOrder.bySizeDescending(files)
            let selectedFile = displayedFiles[interaction]
            baselineSelection.insert(selectedFile.url)
            baselineChecksum &+= selectedFile.byteCount
        }
        let baselineDuration = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let cachedDisplayOrder = FileDisplayOrder.bySizeDescending(files)
        var optimizedSelection = Set<URL>()
        var optimizedChecksum: Int64 = 0
        for interaction in 0 ..< interactionCount {
            let selectedFile = cachedDisplayOrder[interaction]
            optimizedSelection.insert(selectedFile.url)
            optimizedChecksum &+= selectedFile.byteCount
        }
        let optimizedDuration = Self.milliseconds(since: started)
        let improvement = baselineDuration > 0
            ? (baselineDuration - optimizedDuration) / baselineDuration * 100
            : 0

        print(String(
            format: "PERF_COMPARISON storage-file-selection files=%d interactions=%d baseline_ms=%.2f optimized_ms=%.2f improvement_percent=%.1f",
            files.count,
            interactionCount,
            baselineDuration,
            optimizedDuration,
            improvement
        ))

        #expect(optimizedSelection == baselineSelection)
        #expect(optimizedChecksum == baselineChecksum)
    }

    @Test("Selected size compares repeated reduction and incremental accounting")
    func selectedSizeAccountingComparison() {
        let root = URL(fileURLWithPath: "/selected-size-comparison", isDirectory: true)
        let files = (0 ..< 20_000).map { index in
            let name = "item-\(index).dat"
            return ScannedFile(
                url: root.appending(path: name),
                name: name,
                relativePathComponents: [name],
                category: .other,
                byteCount: Int64(index + 1),
                hasKnownByteCount: !index.isMultiple(of: 17)
            )
        }
        let interactionCount = 500

        var baselineSelectedURLs = Set<URL>()
        var baselineByteCount: Int64 = 0
        var started = DispatchTime.now().uptimeNanoseconds
        for interaction in 0 ..< interactionCount {
            baselineSelectedURLs.insert(files[interaction].url)
            baselineByteCount = files.reduce(into: Int64.zero) { total, file in
                if baselineSelectedURLs.contains(file.url), file.hasKnownByteCount {
                    total += file.byteCount
                }
            }
        }
        let baselineDuration = Self.milliseconds(since: started)

        var optimizedSelectedURLs = Set<URL>()
        var optimizedByteCount: Int64 = 0
        started = DispatchTime.now().uptimeNanoseconds
        for interaction in 0 ..< interactionCount {
            let file = files[interaction]
            optimizedSelectedURLs.insert(file.url)
            if file.hasKnownByteCount {
                optimizedByteCount += file.byteCount
            }
        }
        let optimizedDuration = Self.milliseconds(since: started)
        let improvement = baselineDuration > 0
            ? (baselineDuration - optimizedDuration) / baselineDuration * 100
            : 0

        print(String(
            format: "PERF_COMPARISON storage-selected-size files=%d interactions=%d baseline_ms=%.2f optimized_ms=%.2f improvement_percent=%.1f",
            files.count,
            interactionCount,
            baselineDuration,
            optimizedDuration,
            improvement
        ))

        #expect(optimizedSelectedURLs == baselineSelectedURLs)
        #expect(optimizedByteCount == baselineByteCount)
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

private struct LegacyPerformanceFileStateSnapshot: Encodable {
    let schemaVersion = 2
    let directoryBookmark: Data
    let selectedDirectoryName: String
    let files: [LegacyPerformancePersistedFile]
    let skippedFileCount: Int
}

private struct LegacyPerformancePersistedFile: Encodable {
    let name: String
    let relativePathComponents: [String]
    let category: FileCategory
    let byteCount: Int64
    let hasKnownByteCount: Bool
    let creationDate: Date?
    let modificationDate: Date?

    init(_ file: ScannedFile) {
        name = file.name
        relativePathComponents = file.relativePathComponents
        category = file.category
        byteCount = file.byteCount
        hasKnownByteCount = file.hasKnownByteCount
        creationDate = file.creationDate
        modificationDate = file.modificationDate
    }
}
