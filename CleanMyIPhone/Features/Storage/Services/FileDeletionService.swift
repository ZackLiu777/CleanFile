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
        try delete(files: files, selectedRoots: [selectedRoot])
    }

    func delete(
        files: [ScannedFile],
        selectedRoots: [URL]
    ) throws -> FileDeletionResult {
        guard !files.isEmpty else { throw FileDeletionError.noItemsSelected }
        let roots = selectedRoots.map(\.standardizedFileURL)
        guard !roots.isEmpty,
              files.allSatisfy({ file in
                  roots.contains { Self.contains(file.url, root: $0) }
              }) else {
            throw FileDeletionError.invalidSelection
        }

        var deletedURLs = Set<URL>()
        var failedFileCount = 0
        for root in roots {
            let matchingFiles = files.filter {
                !deletedURLs.contains($0.url) && Self.contains($0.url, root: root)
            }
            guard !matchingFiles.isEmpty else { continue }
            guard root.startAccessingSecurityScopedResource() else {
                failedFileCount += matchingFiles.count
                continue
            }
            defer { root.stopAccessingSecurityScopedResource() }

            for file in matchingFiles where !deletedURLs.contains(file.url) {
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
        }

        return FileDeletionResult(
            deletedURLs: deletedURLs,
            failedFileCount: failedFileCount
        )
    }

    /// 判断 `isDescendant` 条件是否成立，供调用方选择正确的处理分支。
    private nonisolated static func contains(_ candidate: URL, root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.starts(with: rootComponents) else { return false }
        if candidateComponents.count == rootComponents.count {
            return !root.hasDirectoryPath
        }
        return true
    }
}
