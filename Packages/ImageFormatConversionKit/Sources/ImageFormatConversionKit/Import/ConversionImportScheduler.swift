//
//  协调各转换页面共用的照片传输与文件导入许可。
//  常态最多两项，高温状态下降为一项；等待者按先进先出顺序恢复。
//  操作结束或抛错都会归还许可，等待期间取消会在取得许可后检查。
//  照片传输和相关文件导入通过共享 actor 申请许可，避免多个页面叠加过多工作。
//  热状态改变会影响后续唤醒时的上限；当前已经执行的操作不会因此自动终止。
//

import Foundation

/// Limits heavyweight PhotoKit and file-I/O operations across every conversion tab.
/// Two active operations keep modern iPhone storage busy without multiplying memory,
/// decode, and thermal pressure. Thermal pressure reduces the limit to one.
actor ConversionImportScheduler {
    static let shared = ConversionImportScheduler()

    private var activeOperations = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var longWaiters: ConversionFIFOQueueCandidate<CheckedContinuation<Void, Never>>?

    /// 取得许可后检查取消并执行操作，无论成功还是抛错都归还许可。
    /// 排队期间的取消不会立即移除等待者，而是在恢复后阻止操作开始。
    func withPermit<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    /// 有空位时立即取得许可，否则按顺序排队；长队列切换到 FIFO 存储。
    private func acquire() async {
        if activeOperations < currentLimit {
            activeOperations += 1
            return
        }
        await withCheckedContinuation { continuation in
            if longWaiters != nil {
                longWaiters?.append(continuation)
            } else {
                waiters.append(continuation)
                if waiters.count >= 1_000 {
                    var queue = ConversionFIFOQueueCandidate<CheckedContinuation<Void, Never>>()
                    for waiter in waiters { queue.append(waiter) }
                    longWaiters = queue
                    waiters.removeAll()
                }
            }
        }
    }

    /// 归还许可并按当前热状态上限唤醒等待者。
    private func release() {
        activeOperations = max(activeOperations - 1, 0)
        while activeOperations < currentLimit {
            let waiter: CheckedContinuation<Void, Never>
            if let next = longWaiters?.popFirst() {
                waiter = next
                if longWaiters?.isEmpty == true { longWaiters = nil }
            } else if !waiters.isEmpty {
                waiter = waiters.removeFirst()
            } else {
                break
            }
            activeOperations += 1
            waiter.resume()
        }
    }

    private var currentLimit: Int {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            1
        case .nominal, .fair:
            2
        @unknown default:
            1
        }
    }
}
