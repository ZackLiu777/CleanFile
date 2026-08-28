//
//  FileDeletionService.swift
//  CleanMyIPhone
//

//
//  文件职责：封装 FileDeletion 领域服务及其边界处理。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 使用 Actor 隔离 `FileDeletionService` 的可变状态，确保并发访问安全。
actor FileDeletionService {
    private let fileManager = FileManager.default

    /// 执行 `delete` 移除流程，并同步更新受影响的业务状态。
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

    /// 判断 `isDescendant` 条件是否成立，供调用方选择正确的处理分支。
    private nonisolated static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}
