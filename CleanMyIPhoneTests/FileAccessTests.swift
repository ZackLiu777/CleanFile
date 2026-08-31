import Foundation
import Testing
@testable import CleanMyIPhone

@Suite("File access boundaries")
struct FileAccessTests {
    @Test("Unrestricted access returns the operation value")
    func unrestrictedAccessReturnsValue() throws {
        let access = UnrestrictedFileAccess()
        let value = try access.withAccess(to: URL(fileURLWithPath: "/tmp/example")) {
            "metadata"
        }

        #expect(value == "metadata")
    }

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

private enum AccessTestError: Error, Equatable {
    case failed
}
