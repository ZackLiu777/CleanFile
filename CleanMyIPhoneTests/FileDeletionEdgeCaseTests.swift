import Foundation
import Testing
@testable import CleanMyIPhone

@Suite("File deletion safety boundaries")
struct FileDeletionEdgeCaseTests {
    @Test("Deleting an empty selection is rejected before touching the file system")
    func emptySelectionIsRejected() async {
        let service = FileDeletionService()
        var receivedError: Error?

        do {
            _ = try await service.delete(
                files: [],
                selectedRoot: URL(fileURLWithPath: "/tmp/clean-file-root", isDirectory: true)
            )
        } catch {
            receivedError = error
        }

        #expect((receivedError as? FileDeletionError) == .noItemsSelected)
    }

    @Test("A selection outside the analyzed folder is rejected atomically")
    func outsideSelectionIsRejected() async {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let outside = ScannedFile(
            url: URL(fileURLWithPath: "/tmp/RootBackup/important.txt"),
            name: "important.txt",
            relativePathComponents: ["important.txt"],
            category: .document,
            byteCount: 1
        )
        let service = FileDeletionService()
        var receivedError: Error?

        do {
            _ = try await service.delete(files: [outside], selectedRoot: root)
        } catch {
            receivedError = error
        }

        #expect((receivedError as? FileDeletionError) == .invalidSelection)
    }

    @Test("Selection validation rejects the root folder itself")
    func rootItselfCannotBeDeleted() async {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let rootItem = ScannedFile(
            url: root,
            name: "Root",
            relativePathComponents: [],
            category: .other,
            byteCount: 0
        )
        let service = FileDeletionService()
        var receivedError: Error?

        do {
            _ = try await service.delete(files: [rootItem], selectedRoot: root)
        } catch {
            receivedError = error
        }

        #expect((receivedError as? FileDeletionError) == .invalidSelection)
    }

    @Test("Deletion result can represent complete and partial outcomes")
    func deletionResultRepresentsOutcomeShape() {
        let first = URL(fileURLWithPath: "/tmp/Root/first.txt")
        let second = URL(fileURLWithPath: "/tmp/Root/second.txt")
        let complete = FileDeletionResult(deletedURLs: [first, second], failedFileCount: 0)
        let partial = FileDeletionResult(deletedURLs: [first], failedFileCount: 1)

        #expect(complete.deletedURLs.count == 2)
        #expect(complete.failedFileCount == 0)
        #expect(partial.deletedURLs == [first])
        #expect(partial.failedFileCount == 1)
    }

    @Test("Deletion state activity is false for all terminal and idle states")
    func deletionStateTerminalStatesAreInactive() {
        let states: [FileDeletionState] = [
            .idle,
            .success(deletedCount: 0),
            .partialFailure(deletedCount: 0, failedCount: 2),
            .failure(.deletionFailed)
        ]

        #expect(states.allSatisfy { !$0.isDeleting })
    }
}
