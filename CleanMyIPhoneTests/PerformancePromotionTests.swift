import Foundation
import Dispatch
import Testing
@testable import CleanMyIPhone
@testable import ImageFormatConversionKit

@Suite("Selective performance promotion", .serialized)
struct PerformancePromotionTests {
    @Test func medianRouting() {
        for count in [0, 2, 3, 999, 1_000, 10_000] {
            let ascending = (0..<count).map(Double.init)
            for values in [ascending, ascending.reversed().map { $0 }, ascending.map { Double(Int($0) * 48271 % 100003) }, ascending.map { Double(Int($0) % 7) }] {
                #expect(MediaCalibrationMedianCandidate.preferredCoefficient(values) == MediaCalibrationMedianCandidate.baselineCoefficient(values))
            }
        }
    }

    @Test func batchRouting() {
        for count in [0, 1, 32, 999, 1_000, 10_000] {
            for shape in 0..<4 {
                let indexes = shape == 1 ? Array((0..<count).reversed()) : (0..<count).map { shape == 2 ? ($0 * 48271) % max(count, 1) : $0 }
                let values = indexes.map { ($0 * (shape == 3 ? 20 : 1), "result-\($0)") }
                #expect(BatchResultOrderingCandidate.preferred(values, total: count * (shape == 3 ? 20 : 1)) == BatchResultOrderingCandidate.original(values))
            }
        }
    }

    @Test func concurrentHashRouting() {
        for shape in 0..<3 {
            let features = (0..<500).map { CandidateFeature(id: "\($0)", perceptualHash: shape == 0 ? 0 : (shape == 1 ? UInt64($0 % 3) : UInt64($0) &* 0x9e3779b97f4a7c15)) }
            let original = SegmentedHammingIndex(features: features)
            let preferred = SegmentedHammingIndex(features: features, pruneDenseBuckets: true)
            for limit in [16, Int.max] {
                let a = original.allPairs(maximumDistance: 16, maximumResults: 32, maximumEvaluationsPerImage: limit, workerCount: 4)
                let b = preferred.allPairs(maximumDistance: 16, maximumResults: 32, maximumEvaluationsPerImage: limit, workerCount: 4)
                #expect(a.map { "\($0.firstIndex):\($0.secondIndex)" }.sorted() == b.map { "\($0.firstIndex):\($0.secondIndex)" }.sorted())
            }
        }
    }

    @Test func promotedTiming() {
        let values = (0..<100_000).map { Double(($0 * 48271) % 100003) }
        let results = values.enumerated().map { (Int($0.element), "result-\($0.offset)") }
        for round in 0..<5 {
            var oldMedian: Double?, newMedian: Double?
            var oldResults: [String] = [], newResults: [String] = []
            measure("median", round, { oldMedian = MediaCalibrationMedianCandidate.baselineCoefficient(values) }, { newMedian = MediaCalibrationMedianCandidate.preferredCoefficient(values) })
            #expect(oldMedian == newMedian)
            measure("batch", round, { oldResults = BatchResultOrderingCandidate.original(results) }, { newResults = BatchResultOrderingCandidate.preferred(results, total: 100_003) })
            #expect(oldResults == newResults)
        }
    }
    private func measure(_ name: String, _ round: Int, _ old: () -> Void, _ new: () -> Void) {
        func time(_ body: () -> Void) -> UInt64 {
            let start = DispatchTime.now().uptimeNanoseconds; body()
            return DispatchTime.now().uptimeNanoseconds - start
        }
        let a: UInt64, b: UInt64
        if round.isMultiple(of: 2) { a = time(old); b = time(new) }
        else { b = time(new); a = time(old) }
        print("PROMOTED_PERF \(name) round=\(round) old_ns=\(a) new_ns=\(b)")
    }
}
