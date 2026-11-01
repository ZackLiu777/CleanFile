// 文件访问抽象的边界测试。
//
// 这些用例验证不受限制的访问实现如何返回操作结果和传播错误，
// 并检查扫描错误是否能够向界面提供非空的本地化说明。
// 测试使用示例 URL，不依赖真实用户文件或安全作用域授权。

import Foundation
import Testing
@testable import CleanMyIPhone

/// 验证文件访问包装层不会吞掉闭包的返回值或失败。
@Suite("File access boundaries")
struct FileAccessTests {
    /// 成功时应原样返回闭包的值，调用方无需额外解包结果。
    @Test("Unrestricted access returns the operation value")
    func unrestrictedAccessReturnsValue() throws {
        let access = UnrestrictedFileAccess()
        let value = try access.withAccess(to: URL(fileURLWithPath: "/tmp/example")) {
            "metadata"
        }

        #expect(value == "metadata")
    }

    /// 闭包抛出的具体错误必须穿过访问层，以便上层区分失败原因。
    @Test("Unrestricted access propagates operation failures")
    func unrestrictedAccessPropagatesErrors() {
        let access = UnrestrictedFileAccess()
        var didThrow = false

        do {
            _ = try access.withAccess(to: URL(fileURLWithPath: "/tmp/example")) { () -> Int in
                throw AccessTestError.failed
            }
        } catch let error as AccessTestError {
            didThrow = error == .failed
        } catch {
            Issue.record("Unexpected access error: \(error)")
        }

        #expect(didThrow)
    }

    /// 各种扫描失败状态都应能提供供用户查看的说明。
    @Test("File scan errors expose stable localized descriptions")
    func scanErrorsHaveDescriptions() {
        let errors: [FileScanError] = [
            .cancelled,
            .notDirectory,
            .unableToEnumerate,
            .securityScopeUnavailable,
            .selectionFailed
        ]

        #expect(errors.allSatisfy { $0.errorDescription?.isEmpty == false })
    }
}

/// 用于区分测试闭包错误与其他意外错误的哨兵值。
private enum AccessTestError: Error, Equatable {
    case failed
}
