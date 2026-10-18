import Foundation
import Dispatch
import Testing
@testable import CleanMyIPhone

@Suite("Performance iteration 05", .serialized)
struct PerformanceIteration05Tests {
    @Test func denseBuckets() throws {
        for n in [0, 1, 40, 300, 2_000] {
            for shape in 0..<3 {
                let features = (0..<n).map { i in
                    CandidateFeature(id: "id-\(i)", perceptualHash: shape == 0 ? 0 : (shape == 1 ? UInt64(i % 9) : UInt64(i) &* 0x9e3779b97f4a7c15))
                }
                let old = SegmentedHammingIndex(features: features)
                let new = SegmentedHammingIndex(features: features, pruneDenseBuckets: true)
                for limit in [1, 16, 4_096] {
                    for results in [0, 1, 32] {
                        var a: [String] = [], b: [String] = []
                        let start = DispatchTime.now().uptimeNanoseconds
                        let aa = old.allPairs(maximumDistance: 16, maximumResults: results, maximumEvaluationsPerImage: limit, workerCount: 1)
                        let middle = DispatchTime.now().uptimeNanoseconds
                        let bb = new.allPairs(maximumDistance: 16, maximumResults: results, maximumEvaluationsPerImage: limit, workerCount: 1)
                        let end = DispatchTime.now().uptimeNanoseconds
                        a = aa.map { "\($0.firstIndex):\($0.secondIndex)" }; b = bb.map { "\($0.firstIndex):\($0.secondIndex)" }
                        #expect(a == b)
                        if n == 2_000, limit == 4_096, results == 32 { print("PERF05 hash shape=\(shape) old_ns=\(middle-start) new_ns=\(end-middle)") }
                    }
                }
            }
        }
    }

    @Test func treeAndSnapshot() throws {
        for n in [0, 1, 1_000, 10_000] {
            let root = URL(fileURLWithPath: "/tmp/synthetic")
            let files = (0..<n).map { i in
                ScannedFile(url: root.appendingPathComponent("\(i)"), name: "file-\(i)", relativePathComponents: ["dir-\(i % 31)", "file-\(i)"], category: .other, byteCount: Int64(i), hasKnownByteCount: i % 11 != 0, creationDate: Date(timeIntervalSince1970: Double(i)))
            }
            var oldTree = FileTreeAccumulator(rootURL: root), newTree = FileTreeAccumulator(rootURL: root)
            for file in files { oldTree.append(file); newTree.append(file) }
            let start = DispatchTime.now().uptimeNanoseconds
            let a = oldTree.makeTree()
            let middle = DispatchTime.now().uptimeNanoseconds
            let b = newTree.makeTreeReleasingStorage()
            let end = DispatchTime.now().uptimeNanoseconds
            #expect(a == b)
            let encoder = JSONEncoder()
            let t0 = DispatchTime.now().uptimeNanoseconds
            let original = FileStateSnapshot(directoryBookmark: Data([1,2]), selectedDirectoryName: "fixture", files: files, skippedFileCount: 3)
            let originalData = try encoder.encode(original)
            let t1 = DispatchTime.now().uptimeNanoseconds
            let candidateData = try encoder.encode(FileSnapshotEncodingCandidate(directoryBookmark: Data([1,2]), selectedDirectoryName: "fixture", files: files, skippedFileCount: 3))
            let t2 = DispatchTime.now().uptimeNanoseconds
            let decoded = try JSONDecoder().decode(FileStateSnapshot.self, from: candidateData)
            #expect(decoded.files == original.files)
            #expect(decoded.schemaVersion == original.schemaVersion)
            #expect(decoded.directoryBookmark == original.directoryBookmark)
            #expect(decoded.skippedFileCount == original.skippedFileCount)
            #expect(decoded.selectedDirectoryName == original.selectedDirectoryName)
            #expect((try JSONSerialization.jsonObject(with: originalData) as? NSDictionary) == (try JSONSerialization.jsonObject(with: candidateData) as? NSDictionary))
            print("PERF05 storage count=\(n) tree_old_ns=\(middle-start) tree_new_ns=\(end-middle) encode_old_ns=\(t1-t0) encode_new_ns=\(t2-t1)")
        }
    }
    @Test func snapshotReadAndCancellation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = FileStateSnapshot(directoryBookmark: Data([5]), selectedDirectoryName: "synthetic", files: [], skippedFileCount: 0)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        let loaded = try FileSnapshotEncodingCandidate.decode(from: url)
        #expect(loaded.directoryBookmark == snapshot.directoryBookmark)
        #expect(loaded.files.isEmpty)
        try Data("invalid json".utf8).write(to: url, options: .atomic)
        #expect(throws: (any Error).self) { try FileSnapshotEncodingCandidate.decode(from: url) }
        let cancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try FileSnapshotEncodingCandidate.decode(from: url); return false }
            catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(cancelled)
    }

    @Test func repeatedComparison() throws {
        let root = URL(fileURLWithPath: "/tmp/synthetic")
        let files = (0..<10_000).map { i in
            ScannedFile(url: root.appendingPathComponent("\(i)"), name: "f\(i)", relativePathComponents: ["d\(i % 31)", "f\(i)"], category: .other, byteCount: Int64(i))
        }
        let encoder = JSONEncoder()
        let original = { try encoder.encode(FileStateSnapshot(directoryBookmark: Data(), selectedDirectoryName: "synthetic", files: files, skippedFileCount: 0)) }
        let candidate = { try encoder.encode(FileSnapshotEncodingCandidate(directoryBookmark: Data(), selectedDirectoryName: "synthetic", files: files, skippedFileCount: 0)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try original().write(to: url, options: .atomic)
        _ = try original(); _ = try candidate()
        for round in 0..<5 {
            try measure("snapshot-encode", round, { _ = try original() }, { _ = try candidate() })
            try measure("snapshot-read", round, { _ = try JSONDecoder().decode(FileStateSnapshot.self, from: Data(contentsOf: url)) }, { _ = try FileSnapshotEncodingCandidate.decode(from: url) })
            try measure("tree-build-finalize", round, {
                var tree = FileTreeAccumulator(rootURL: root)
                for file in files { tree.append(file) }
                _ = tree.makeTree()
            }, {
                var tree = FileTreeAccumulator(rootURL: root)
                for file in files { tree.append(file) }
                _ = tree.makeTreeReleasingStorage()
            })
        }
        for shape in 0..<3 {
            let features = (0..<2_000).map { i in CandidateFeature(id: "id-\(i)", perceptualHash: shape == 0 ? 0 : (shape == 1 ? UInt64(i % 9) : UInt64(i) &* 0x9e3779b97f4a7c15)) }
            let old = SegmentedHammingIndex(features: features)
            let new = SegmentedHammingIndex(features: features, pruneDenseBuckets: true)
            for round in 0..<5 {
                try measure("hash-\(shape)", round, { _ = old.allPairs(maximumDistance: 16, maximumResults: 32, maximumEvaluationsPerImage: 4_096, workerCount: 1) }, { _ = new.allPairs(maximumDistance: 16, maximumResults: 32, maximumEvaluationsPerImage: 4_096, workerCount: 1) })
            }
        }
    }

    private func measure(_ name: String, _ round: Int, _ old: () throws -> Void, _ new: () throws -> Void) throws {
        func clock(_ body: () throws -> Void) rethrows -> UInt64 {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            return DispatchTime.now().uptimeNanoseconds - start
        }
        let a: UInt64, b: UInt64
        if round.isMultiple(of: 2) { a = try clock(old); b = try clock(new) }
        else { b = try clock(new); a = try clock(old) }
        let record: [String: Any] = ["name": name, "round": round, "old_ns": a, "new_ns": b]
        print("PERF05_JSON " + String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self))
    }

}
