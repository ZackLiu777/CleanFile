//
//  性能迭代 02
//
//  比较中位数计算和 FIFO 队列的基线与候选实现。
//  正确性用例覆盖输入分布、队列顺序和释放；性能比较单独记录。
//  中位数对照排序基线，覆盖有序、重复、特殊数值和大样本输入。
//  队列检查可选空值、先入先出与出队引用释放；比较轮换执行顺序。
//

import Dispatch
import Foundation
import Testing
@testable import CleanMyIPhone
@testable import ImageFormatConversionKit

/// 对比中位数与 FIFO 候选的结果，并检查队列生命周期。
@Suite("Performance iteration 02 correctness", .serialized)
struct PerformanceIteration02CorrectnessTests {
    /// 对多种样本规模及分布，比较候选中位数与排序基线。
    @Test("Median agrees with the original sort across size and input distributions")
    func medianEquivalence() {
        for count in [0, 1, 2, 3, 4, 127, 128, 129, 1_024, 10_001] {
            for shape in MedianFixture.Shape.allCases {
                let values = MedianFixture.values(count: count, shape: shape)
                #expect(MediaCalibrationMedianCandidate.coefficient(values) == LegacyCalibrationMedian.coefficient(values))
            }
        }
    }

    /// 非有限值使用基线回退，保持已有数值语义。
    @Test("Nonfinite inputs keep the sort fallback and its numerical result")
    func nonfiniteMedian() {
        for values in [
            Array(repeating: 1.0, count: 128) + [.infinity],
            [-Double.infinity] + Array(repeating: 2.0, count: 128),
            [-Double.infinity, Double.infinity, Double.infinity, -Double.infinity]
        ] {
            let actual = MediaCalibrationMedianCandidate.coefficient(values)
            let expected = LegacyCalibrationMedian.coefficient(values)
            #expect(actual == expected || (actual?.isNaN == true && expected?.isNaN == true))
        }
    }

    /// 交错入队、出队、压缩及复用过程中始终保持 FIFO 顺序。
    @Test("FIFO preserves ordering through compaction, interleaving and reuse")
    func fifoOrdering() {
        var expected: [Int] = []
        var candidate = ConversionFIFOQueueCandidate<Int>()
        let initiallyEmpty = candidate.popFirst()
        #expect(initiallyEmpty == nil)
        for phase in 0..<4 {
            for value in 0..<3_001 {
                let token = phase * 10_000 + value
                expected.append(token)
                candidate.append(token)
                if value.isMultiple(of: 3) {
                    let actual = candidate.popFirst()
                    let original = expected.removeFirst()
                    #expect(actual == original)
                }
            }
            #expect(candidate.count == expected.count)
            while !expected.isEmpty {
                let actual = candidate.popFirst()
                let original = expected.removeFirst()
                #expect(actual == original)
            }
            #expect(candidate.isEmpty)
            let empty = candidate.popFirst()
            #expect(empty == nil)
        }
    }

    /// 验证已入队的 nil 值与空队列返回值可区分，并保持后续元素顺序。
    @Test("A nil optional payload is distinct from an empty FIFO")
    func optionalPayload() {
        var candidate = ConversionFIFOQueueCandidate<Int?>()
        candidate.append(nil)
        candidate.append(7)
        let first: Int?? = candidate.popFirst()
        switch first {
        case .some(.none): break
        default: Issue.record("Lost an explicitly enqueued nil payload")
        }
        let second = candidate.popFirst()
        #expect(second == .some(.some(7)))
        #expect(candidate.isEmpty)
    }

    /// 出队后的引用应及时释放，不必等到队列存储压缩。
    @Test("Dequeued reference payloads are released before prefix compaction")
    func releasesPayload() {
        var candidate = ConversionFIFOQueueCandidate<QueueLifetimeToken>()
        weak var first: QueueLifetimeToken?
        do {
            let token = QueueLifetimeToken()
            first = token
            candidate.append(token)
            candidate.append(QueueLifetimeToken())
        }
        #expect(first != nil)
        _ = candidate.popFirst()
        #expect(first == nil)
        #expect(candidate.count == 1)
    }
}

/// 在不同输入规模和形状下记录候选与基线的执行时间。
@Suite("Performance iteration 02 comparisons", .serialized)
struct PerformanceIteration02ComparisonTests {
    /// 在多种规模和分布下记录中位数候选及排序基线，逐次检查结果一致。
    @Test("Compare median construction, including favorable and adversarial inputs")
    func medianPerformance() throws {
        for count in [32, 1_000, 10_000, 100_000] {
            for shape in MedianFixture.Shape.allCases {
                let values = MedianFixture.values(count: count, shape: shape)
                for sample in 0..<5 {
                    let pair = paired(sample: sample, baseline: {
                        MediaCalibrationMedianCandidate.baselineCoefficient(values)
                    }, candidate: {
                        MediaCalibrationMedianCandidate.coefficient(values)
                    })
                    let equivalent = pair.baseline.value == pair.candidate.value
                    #expect(equivalent)
                    try emit(experiment: "calibration-median", scenario: shape.rawValue,
                             count: count, sample: sample, pair: pair, equivalent: equivalent)
                }
            }
        }
    }

    /// 比较完整入队和清空周期；小队列重复执行以降低时钟开销的影响。
    @Test("Compare whole FIFO lifecycles from normal to stress queue lengths")
    func fifoPerformance() throws {
        for count in [1, 2, 8, 32, 1_000, 10_000, 50_000] {
            let inputs = Array(0..<count)
            // Small queues need repetition to rise above clock overhead. Both
            // sides repeat complete enqueue/dequeue cycles the same number of times.
            let cycles = count <= 32 ? 1_000 : 1
            for sample in 0..<5 {
                let pair = paired(sample: sample, baseline: {
                    ConversionFIFOComparisonCandidate.legacyLifecycle(inputs, cycles: cycles)
                }, candidate: {
                    ConversionFIFOComparisonCandidate.proposedLifecycle(inputs, cycles: cycles)
                })
                let equivalent = pair.baseline.value == pair.candidate.value
                #expect(equivalent)
                try emit(experiment: "import-waiter-fifo", scenario: "enqueue-and-drain",
                         count: count, sample: sample, pair: pair, equivalent: equivalent,
                         cycles: cycles)
            }
        }
    }

    /// 执行一次闭包并记录返回值和单调时钟耗时。
    private func measure<Value>(_ operation: () -> Value) -> TimedValue<Value> {
        let started = DispatchTime.now().uptimeNanoseconds
        let value = operation()
        return TimedValue(value: value, nanoseconds: DispatchTime.now().uptimeNanoseconds - started)
    }

    /// 按样本序号交替两条路径的执行顺序，减轻固定先后顺序的偏差。
    private func paired<Value>(sample: Int, baseline: () -> Value, candidate: () -> Value) -> Pair<Value> {
        if sample.isMultiple(of: 2) {
            let original = measure(baseline)
            return Pair(baseline: original, candidate: measure(candidate))
        }
        let proposed = measure(candidate)
        return Pair(baseline: measure(baseline), candidate: proposed)
    }

    /// 输出比较结果、执行范围和队列元素步长，供后续分析实验数据。
    private func emit<Value>(experiment: String, scenario: String, count: Int, sample: Int,
                             pair: Pair<Value>, equivalent: Bool, cycles: Int = 1) throws {
        let data = try JSONEncoder().encode(Iteration02Timing(
            experiment: experiment, scenario: scenario, asset_count: count, sample: sample,
            baseline_ns: pair.baseline.nanoseconds, candidate_ns: pair.candidate.nanoseconds,
            equivalent: equivalent, cycles: cycles,
            scope: experiment == "calibration-median" ? "single-calibration-bucket-only" : "int-fifo-container-only",
            baseline_element_stride: experiment == "import-waiter-fifo" ? MemoryLayout<Int>.stride : nil,
            candidate_element_stride: experiment == "import-waiter-fifo" ? MemoryLayout<Int?>.stride : nil
        ))
        print("PERF_ITERATION02_JSON \(String(decoding: data, as: UTF8.self))")
    }
}

/// 将计算结果与对应的纳秒耗时保存在一起。
private struct TimedValue<Value> {
    let value: Value
    let nanoseconds: UInt64
}

/// 保存同一轮基线和候选实现的测量结果。
private struct Pair<Value> {
    let baseline: TimedValue<Value>
    let candidate: TimedValue<Value>
}

/// 记录实验输入、耗时、等价性和测量范围的可编码数据。
private struct Iteration02Timing: Encodable {
    let experiment: String
    let scenario: String
    let asset_count: Int
    let sample: Int
    let baseline_ns: UInt64
    let candidate_ns: UInt64
    let equivalent: Bool
    let cycles: Int
    let scope: String
    let baseline_element_stride: Int?
    let candidate_element_stride: Int?
}

/// 保留排序型中位数基线，供正确性和耗时比较。
private enum LegacyCalibrationMedian {
    /// 少于三个样本返回空值；否则排序后取中位数，偶数样本取中间均值。
    static func coefficient(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// 提供可复现的中位数输入，覆盖不同大小和数据形状。
private enum MedianFixture {
    /// 列举乱序、升降序、重复值和先升后降的测试分布。
    enum Shape: String, CaseIterable {
        case shuffled, ascending, descending, duplicates, organPipe
    }

    /// 按指定数量和形状生成确定性数值，不依赖随机种子。
    static func values(count: Int, shape: Shape) -> [Double] {
        (0..<count).map { index in
            switch shape {
            case .shuffled: Double((index &* 7_919 &+ 17) % max(count, 1)) / 7
            case .ascending: Double(index) / 7
            case .descending: Double(count - index) / 7
            case .duplicates: Double(index % 3)
            case .organPipe: Double(min(index, count - index)) / 7
            }
        }
    }
}

/// 弱引用生命周期测试使用的空引用对象。
private final class QueueLifetimeToken: Sendable {}
