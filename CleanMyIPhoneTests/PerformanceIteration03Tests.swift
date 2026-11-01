//
//  性能迭代 03
//
//  对照大文件选择和来源去重的新旧实现。
//  使用多种数据形状和规模验证结果一致并记录计时。
//  大文件前十项和标准化来源去重均与原实现逐项比较。
//  输入为不同分布的合成文件与 URL；记录仅用于比较，不承诺运行速度。
//

import Foundation
import Dispatch
import Testing
@testable import CleanMyIPhone

/// 比较大文件选择与来源去重的结果和性能。
@Suite("Storage performance iteration 03", .serialized)
struct PerformanceIteration03Tests {
    /// 对多种数量和数据分布比较前十文件及来源去重结果。
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

    /// 交替执行新旧路径并记录耗时，同时断言每次输出一致。
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

    /// 生成不同大小分布和部分未知大小的合成文件记录。
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
    /// 返回闭包执行消耗的单调时钟纳秒数。
    private func timed(_ body: () -> Void) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return DispatchTime.now().uptimeNanoseconds - start
    }
    /// 将本轮实验规模、形状、耗时和结果等价性输出为 JSON。
    private func record(_ experiment: String, _ count: Int, _ shape: Int, _ round: Int, _ old: UInt64, _ new: UInt64, _ equal: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: ["experiment": experiment, "count": count, "shape": shape, "round": round, "old_ns": old, "new_ns": new, "equal": equal], options: [.sortedKeys])
        print("PERF03 " + String(decoding: data, as: UTF8.self))
    }
}
