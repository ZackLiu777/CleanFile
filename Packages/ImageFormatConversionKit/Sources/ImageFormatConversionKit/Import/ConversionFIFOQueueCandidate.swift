//
//  为导入调度器的长等待队列提供先进先出存储及对照实现。
//  出队立即释放元素，只有消耗足够多的前缀后才批量压缩存储。
//  对照生命周期用于比较队列策略，避免频繁移除数组首项造成反复搬移。
//  调度器在等待者较多时使用队列，短队列仍沿用数组。
//  该结构只管理等待顺序与元素生命周期，不决定许可数量或执行实际导入。
//

/// 长等待队列使用的 FIFO；短队列仍由调度器使用普通数组。
struct ConversionFIFOQueueCandidate<Element: Sendable>: Sendable {
    private var storage: [Element?] = []
    private var head = 0

    var count: Int { storage.count - head }
    var isEmpty: Bool { count == 0 }

    /// 将等待者加入队尾。
    mutating func append(_ value: Element) {
        storage.append(.some(value))
    }

    /// 移除队首并及时释放引用，按阈值摊销前缀压缩成本。
    mutating func popFirst() -> Element? {
        guard head < storage.count else { return nil }
        let value = storage[head]
        // Release the waiter as soon as it is dequeued, including reference
        // payloads; do not retain completed continuations until compaction.
        storage[head] = nil
        head += 1
        if head == storage.count {
            storage.removeAll(keepingCapacity: true)
            head = 0
        } else if head >= 1_024, head >= storage.count - head {
            // Reclaim the consumed prefix only after enough pops to amortize
            // the remaining copy. Total draining work is linear, not quadratic.
            storage.removeFirst(head)
            head = 0
        }
        return value
    }
}

/// Keep both timed lifecycles in this module. Comparing an inlined test-local
/// Array with an opaque cross-module generic FIFO would bias the experiment.
enum ConversionFIFOComparisonCandidate {
    /// 使用数组首项移除完成一组入队和出队周期，返回校验和。
    static func legacyLifecycle(_ inputs: [Int], cycles: Int) -> Int {
        var checksum = 0
        for _ in 0..<cycles {
            var queue: [Int] = []
            for input in inputs { queue.append(input) }
            while !queue.isEmpty { checksum &+= queue.removeFirst() }
        }
        return checksum
    }

    /// 使用候选 FIFO 完成相同周期，返回可与基线比较的校验和。
    static func proposedLifecycle(_ inputs: [Int], cycles: Int) -> Int {
        var checksum = 0
        for _ in 0..<cycles {
            var queue = ConversionFIFOQueueCandidate<Int>()
            for input in inputs { queue.append(input) }
            while let value = queue.popFirst() { checksum &+= value }
        }
        return checksum
    }
}
