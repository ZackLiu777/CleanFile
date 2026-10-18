/// FIFO for long import backlogs. Short backlogs retain the scheduler’s original array.
struct ConversionFIFOQueueCandidate<Element: Sendable>: Sendable {
    private var storage: [Element?] = []
    private var head = 0

    var count: Int { storage.count - head }
    var isEmpty: Bool { count == 0 }

    mutating func append(_ value: Element) {
        storage.append(.some(value))
    }

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
    static func legacyLifecycle(_ inputs: [Int], cycles: Int) -> Int {
        var checksum = 0
        for _ in 0..<cycles {
            var queue: [Int] = []
            for input in inputs { queue.append(input) }
            while !queue.isEmpty { checksum &+= queue.removeFirst() }
        }
        return checksum
    }

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
