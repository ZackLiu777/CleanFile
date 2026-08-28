//
//  文件职责：集中定义 ConversionImportScheduler 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import Foundation

/// Limits heavyweight PhotoKit and file-I/O operations across every conversion tab.
/// Two active operations keep modern iPhone storage busy without multiplying memory,
/// decode, and thermal pressure. Thermal pressure reduces the limit to one.
actor ConversionImportScheduler {
    static let shared = ConversionImportScheduler()

    private var activeOperations = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// 封装 `withPermit` 对应的局部行为，供当前类型在统一入口下复用。
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

    /// 封装 `acquire` 对应的局部行为，供当前类型在统一入口下复用。
    private func acquire() async {
        if activeOperations < currentLimit {
            activeOperations += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// 封装 `release` 对应的局部行为，供当前类型在统一入口下复用。
    private func release() {
        activeOperations = max(activeOperations - 1, 0)
        while activeOperations < currentLimit, !waiters.isEmpty {
            activeOperations += 1
            waiters.removeFirst().resume()
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
