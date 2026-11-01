//
//  媒体大小请求队列
//
//  以 FIFO 顺序管理资源标识，并为长队列延迟清理已消费前缀。
//  对比实现保留用于衡量队列策略，队列本身不访问 PhotoKit 或读取文件。
//

import Foundation

/// Long-request backlog FIFO; short backlogs keep the ViewModel’s original array.
nonisolated struct MediaSizeRequestQueue {
    private var storage: [String] = []
    private var head = 0

    var count: Int { storage.count - head }
    var isEmpty: Bool { count == 0 }

    /// 将资源标识追加到队尾，保持请求顺序。
    mutating func append(_ identifier: String) { storage.append(identifier) }

    /// 移除队首；长队列通过移动头指针减少反复搬移，并在合适时机压缩存储。
    mutating func popFirst() -> String? {
        // Compaction always resets head; a short backing array therefore has no consumed prefix.
        if storage.count <= 32 { return storage.isEmpty ? nil : storage.removeFirst() }
        guard head < storage.count else { return nil }
        let identifier = storage[head]
        storage[head] = ""
        head += 1
        if head == storage.count {
            storage.removeAll(keepingCapacity: true)
            head = 0
        } else if head >= 1_024, head >= storage.count - head {
            storage.removeFirst(head)
            head = 0
        }
        return identifier
    }

    /// 清空队列和消费位置，使实例可安全复用。
    mutating func removeAll() {
        storage.removeAll()
        head = 0
    }
}

/// Both timed paths live in the same module and include enqueue/dequeue work.
/// 保留原数组与新队列的相同工作量入口，以便比较长队列的处理成本。
nonisolated enum MediaSizeRequestQueueComparison {
    /// 以数组移除首项的方式完成指定轮次并返回校验和。
    static func original(_ identifiers: [String], cycles: Int) -> Int {
        var checksum = 0
        for _ in 0..<cycles {
            var queue: [String] = []
            for identifier in identifiers { queue.append(identifier) }
            while !queue.isEmpty { checksum &+= queue.removeFirst().utf8.count }
        }
        return checksum
    }

    /// 使用队列完成相同轮次并返回校验和，供比较调用方校验结果。
    static func proposed(_ identifiers: [String], cycles: Int) -> Int {
        var checksum = 0
        for _ in 0..<cycles {
            var queue = MediaSizeRequestQueue()
            for identifier in identifiers { queue.append(identifier) }
            while let identifier = queue.popFirst() { checksum &+= identifier.utf8.count }
        }
        return checksum
    }
}
