import Foundation
import Testing
@testable import ImageFormatConversionKit

@Suite("Conversion import scheduler")
struct ConversionImportSchedulerTests {
    @Test("A permit returns the operation value")
    func permitReturnsOperationValue() async throws {
        let scheduler = ConversionImportScheduler()

        let value = try await scheduler.withPermit {
            "completed"
        }

        #expect(value == "completed")
    }

    @Test("Operation errors release the permit and propagate unchanged")
    func operationErrorPropagates() async {
        let scheduler = ConversionImportScheduler()
        var didThrow = false

        do {
            let _: String = try await scheduler.withPermit {
                throw SchedulerTestError.failed
            }
        } catch let error as SchedulerTestError {
            didThrow = error == .failed
        } catch {
            Issue.record("Unexpected scheduler error: \(error)")
        }

        #expect(didThrow)
        let value = try? await scheduler.withPermit { 42 }
        #expect(value == 42)
    }

    @Test("A cancelled task does not execute its operation")
    func cancelledTaskSkipsOperation() async {
        let scheduler = ConversionImportScheduler()
        let didRun = RunFlag()
        let task = Task {
            try Task.checkCancellation()
            try await scheduler.withPermit {
                didRun.mark()
                return 1
            }
        }
        task.cancel()
        _ = try? await task.value

        #expect(!didRun.value)
    }
}

private enum SchedulerTestError: Error, Equatable {
    case failed
}

private final class RunFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func mark() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}
