import Foundation
import Dispatch
import Testing
@testable import CleanMyIPhone
@testable import ImageFormatConversionKit

@Suite("Performance iteration 04", .serialized)
struct PerformanceIteration04Tests {
    @Test func queueCorrectness() {
        var queue = MediaSizeRequestQueue()
        var expected: [String] = []
        for phase in 0..<3 {
            for i in 0..<5_000 {
                let value = i % 13 == 0 ? "" : "identifier-\(phase)-\(i)"
                queue.append(value); expected.append(value)
                if i % 3 == 0 {
                    let actual = queue.popFirst()
                    #expect(actual == expected.removeFirst())
                }
                #expect(queue.count == expected.count)
            }
            if phase == 1 { queue.removeAll(); expected.removeAll() }
            while !expected.isEmpty {
                let actual = queue.popFirst()
                #expect(actual == expected.removeFirst())
            }
            let empty = queue.popFirst()
            #expect(empty == nil)
            #expect(queue.isEmpty)
        }
    }

    @Test func orderingCorrectness() {
        for count in [0, 1, 32, 33, 100, 1_000] {
            for step in [1, 2, 20] {
                let values = (0..<count).reversed().map { ($0 * step, "result-\($0)") }
                #expect(BatchResultOrderingCandidate.proposed(values, total: count * step) == BatchResultOrderingCandidate.original(values))
            }
        }
        for indexes in [Array(repeating: 2, count: 40), Array(-20..<20), Array(20..<60)] {
            let values = indexes.map { ($0, "\($0)") }
            #expect(BatchResultOrderingCandidate.proposed(values, total: 40) == BatchResultOrderingCandidate.original(values))
        }
    }

    @Test func performance() throws {
        for count in [1, 8, 32, 1_000, 10_000, 50_000] {
            let values = (0..<count).map { "synthetic-photo-identifier-\($0)/L0/001" }
            let cycles = count <= 32 ? 1_000 : 1
            for round in 0..<5 {
                var old = 0, new = 0
                let times = timedPair(round, { old = MediaSizeRequestQueueComparison.original(values, cycles: cycles) }, { new = MediaSizeRequestQueueComparison.proposed(values, cycles: cycles) })
                #expect(old == new)
                try record("media-queue", count, "fifo", cycles, round, times, old == new)
            }
        }
        for count in [8, 1_000, 100_000] {
            for shape in 0..<4 {
                var indexes = Array(0..<count)
                if shape == 1 { indexes.reverse() }
                if shape == 2 {
                    var seed: UInt64 = 42
                    for i in indexes.indices.reversed() where i > 0 {
                        seed = seed &* 6364136223846793005 &+ 1
                        indexes.swapAt(i, Int(seed % UInt64(i + 1)))
                    }
                }
                let step = shape == 3 ? 20 : 1
                let values = indexes.map { ($0 * step, "result-\($0)") }
                for round in 0..<5 {
                    var old: [String] = [], new: [String] = []
                    let times = timedPair(round, { old = BatchResultOrderingCandidate.original(values) }, { new = BatchResultOrderingCandidate.proposed(values, total: count * step) })
                    #expect(old == new)
                    try record("batch-order", count, ["ascending", "descending", "shuffled", "sparse"][shape], 1, round, times, old == new)
                }
            }
        }
    }
    private func timedPair(_ round: Int, _ old: () -> Void, _ new: () -> Void) -> (UInt64, UInt64) {
        var a: UInt64 = 0, b: UInt64 = 0
        if round.isMultiple(of: 2) { a = timed(old); b = timed(new) }
        else { b = timed(new); a = timed(old) }
        return (a, b)
    }
    private func timed(_ body: () -> Void) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return DispatchTime.now().uptimeNanoseconds - start
    }
    private func record(_ experiment: String, _ count: Int, _ shape: String, _ cycles: Int, _ round: Int, _ times: (UInt64, UInt64), _ equal: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: ["experiment": experiment, "count": count, "shape": shape, "cycles": cycles, "round": round, "old_ns": times.0, "new_ns": times.1, "equal": equal], options: [.sortedKeys])
        print("PERF04 " + String(decoding: data, as: UTF8.self))
    }
}
