//
//  验证导入调度许可返回值、错误传播和任务取消行为。
//  失败后再次取得许可，检查操作结束时资源能够归还。
//  使用隔离的标记记录操作是否被调用。
//  取消任务不得执行闭包；操作抛错后许可仍可供后续请求使用。
//  测试替身只记录闭包调用，不导入真实文件。
//

import Foundation
import Testing
@testable import ImageFormatConversionKit

/// 检查许可的成功、失败和取消路径。
@Suite("Conversion import scheduler")
struct ConversionImportSchedulerTests {
    /// 成功取得许可后，调度器应原样返回操作的结果。
    @Test("A permit returns the operation value")
    func permitReturnsOperationValue() async throws {
        let scheduler = ConversionImportScheduler()

        let value = try await scheduler.withPermit {
            "completed"
        }

        #expect(value == "completed")
    }

    /// 操作失败后检查原始错误，并再次获取许可验证归还。
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

    /// 取消任务后检查许可内的操作未被执行。
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

/// 区分测试操作抛出的错误与调度器可能产生的其他错误。
private enum SchedulerTestError: Error, Equatable {
    case failed
}

/// 使用锁保护跨任务访问的执行标记，供取消用例观察操作是否发生。
private final class RunFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    /// 在锁内读取执行标记的当前值。
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// 将标记设为已执行，供主测试任务读取。
    func mark() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}
