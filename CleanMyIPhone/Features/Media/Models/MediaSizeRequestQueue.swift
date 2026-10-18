import Foundation

/// Long-request backlog FIFO; short backlogs keep the ViewModel’s original array.
nonisolated struct MediaSizeRequestQueue {
    private var storage: [String] = []
    private var head = 0

    var count: Int { storage.count - head }
    var isEmpty: Bool { count == 0 }

    mutating func append(_ identifier: String) { storage.append(identifier) }

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

    mutating func removeAll() {
        storage.removeAll()
        head = 0
    }
}

/// Both timed paths live in the same module and include enqueue/dequeue work.
nonisolated enum MediaSizeRequestQueueComparison {
    static func original(_ identifiers: [String], cycles: Int) -> Int {
        var checksum = 0
        for _ in 0..<cycles {
            var queue: [String] = []
            for identifier in identifiers { queue.append(identifier) }
            while !queue.isEmpty { checksum &+= queue.removeFirst().utf8.count }
        }
        return checksum
    }

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
