import Foundation

/// Limits heavyweight PhotoKit and file-I/O operations across every conversion tab.
/// Two active operations keep modern iPhone storage busy without multiplying memory,
/// decode, and thermal pressure. Thermal pressure reduces the limit to one.
actor ConversionImportScheduler {
    static let shared = ConversionImportScheduler()

    private var activeOperations = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

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

    private func acquire() async {
        if activeOperations < currentLimit {
            activeOperations += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

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
