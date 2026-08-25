//
//  FileDeletionService.swift
//  CleanMyIPhone
//

import Foundation

actor FileDeletionService {
    private let fileManager = FileManager.default

    func delete(
        files: [ScannedFile],
        selectedRoot: URL
    ) throws -> FileDeletionResult {
        guard !files.isEmpty else { throw FileDeletionError.noItemsSelected }

        let root = selectedRoot.standardizedFileURL
        guard files.allSatisfy({ Self.isDescendant($0.url, of: root) }) else {
            throw FileDeletionError.invalidSelection
        }
        guard root.startAccessingSecurityScopedResource() else {
            throw FileDeletionError.folderAccessUnavailable
        }
        defer { root.stopAccessingSecurityScopedResource() }

        var deletedURLs = Set<URL>()
        var failedFileCount = 0
        for file in files {
            do {
                try Task.checkCancellation()
                try fileManager.removeItem(at: file.url)
                deletedURLs.insert(file.url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedFileCount += 1
            }
        }

        return FileDeletionResult(
            deletedURLs: deletedURLs,
            failedFileCount: failedFileCount
        )
    }

    private nonisolated static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}
