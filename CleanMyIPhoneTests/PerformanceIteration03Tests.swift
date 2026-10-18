import Foundation
import Dispatch
import Testing
@testable import CleanMyIPhone

@Suite("Storage performance iteration 03", .serialized)
struct PerformanceIteration03Tests {
    @Test func correctness() {
        for count in [0, 1, 9, 10, 11, 128, 1001] {
            for shape in 0..<4 {
                let files = fixture(count, shape)
                #expect(StorageSelectionAlgorithms.largest(files) == StorageSelectionAlgorithms.originalLargest(files))
            }
        }
        let urls = ["/tmp/a/../b", "/tmp/b", "/tmp/c", "/tmp/c/", "/tmp/B"].map { URL(fileURLWithPath: $0) }
        #expect(StorageSelectionAlgorithms.sources(urls) == StorageSelectionAlgorithms.originalSources(urls))
        #expect(StorageSelectionAlgorithms.sources([]).isEmpty)
    }

    @Test func comparison() throws {
        for count in [10, 1_000, 100_000, 500_000] {
            for shape in 0..<4 {
                let input = fixture(count, shape)
                for round in 0..<5 {
                    var old: [ScannedFile] = [], new: [ScannedFile] = []
                    var a: UInt64 = 0, b: UInt64 = 0
                    if round.isMultiple(of: 2) {
                        a = timed { old = StorageSelectionAlgorithms.originalLargest(input) }
                        b = timed { new = StorageSelectionAlgorithms.largest(input) }
                    } else {
                        b = timed { new = StorageSelectionAlgorithms.largest(input) }
                        a = timed { old = StorageSelectionAlgorithms.originalLargest(input) }
                    }
                    #expect(old == new)
                    try record("top10", count, shape, round, a, b, old == new)
                }
            }
        }
        for count in [1, 10, 100, 1_000] {
            for shape in 0..<2 {
                let input = (0..<count).map { URL(fileURLWithPath: "/tmp/synthetic/\(shape == 0 ? $0 : $0 % 10)") }
                for round in 0..<5 {
                    var old: [URL] = [], new: [URL] = []
                    var a: UInt64 = 0, b: UInt64 = 0
                    if round.isMultiple(of: 2) {
                        a = timed { old = StorageSelectionAlgorithms.originalSources(input) }
                        b = timed { new = StorageSelectionAlgorithms.sources(input) }
                    } else {
                        b = timed { new = StorageSelectionAlgorithms.sources(input) }
                        a = timed { old = StorageSelectionAlgorithms.originalSources(input) }
                    }
                    #expect(old == new)
                    try record("sources", count, shape, round, a, b, old == new)
                }
            }
        }
    }

    private func fixture(_ count: Int, _ shape: Int) -> [ScannedFile] {
        (0..<count).map { i in
            let size = switch shape {
            case 0: Int64((i * 48271) % 100003)
            case 1: Int64(i)
            case 2: Int64(count - i)
            default: Int64(i % 3 - 1)
            }
            return ScannedFile(url: URL(fileURLWithPath: "/tmp/synthetic/\(i)"), name: "\(i)", relativePathComponents: ["\(i)"], category: .other, byteCount: size, hasKnownByteCount: i % 7 != 0)
        }
    }
    private func timed(_ body: () -> Void) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return DispatchTime.now().uptimeNanoseconds - start
    }
    private func record(_ experiment: String, _ count: Int, _ shape: Int, _ round: Int, _ old: UInt64, _ new: UInt64, _ equal: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: ["experiment": experiment, "count": count, "shape": shape, "round": round, "old_ns": old, "new_ns": new, "equal": equal], options: [.sortedKeys])
        print("PERF03 " + String(decoding: data, as: UTF8.self))
    }
}
