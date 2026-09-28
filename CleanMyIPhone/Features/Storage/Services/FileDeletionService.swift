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
        // Keep the original URLs carrying the document picker's access grant.
        let roots = selectedRoots
        // Resolve filesystem aliases only while the original grants are active.
        let accessibleRoots = roots.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessibleRoots.forEach { $0.stopAccessingSecurityScopedResource() } }
        guard !roots.isEmpty,
              files.allSatisfy({ file in
                  roots.contains { Self.contains(file.url, root: $0) }
              }) else {
            #if DEBUG
            debugPrint("Storage deletion rejected: canonical directory boundary mismatch")
            debugPrint("Storage deletion grants: roots=\(roots.count), active=\(accessibleRoots.count), files=\(files.count)")
            // Report only structural facts: provider paths and filenames can
            // contain personal information and must not enter the console.
            if let file = files.first(where: { file in
                !roots.contains { Self.contains(file.url, root: $0) }
            }) {
                for root in roots.prefix(3) {
                    let rawRoot = root.standardizedFileURL.pathComponents
                    let rawFile = file.url.standardizedFileURL.pathComponents
                    let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                    let resolvedFile = file.url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                    debugPrint("Storage deletion boundary: fileURLs=\(root.isFileURL)/\(file.url.isFileURL), lexicalPrefix=\(rawFile.starts(with: rawRoot)), canonicalPrefix=\(resolvedFile.starts(with: resolvedRoot)), depths=\(rawRoot.count)/\(rawFile.count)/\(resolvedRoot.count)/\(resolvedFile.count), rootDirectoryHint=\(root.hasDirectoryPath), trailingSeparator=\(rawRoot.last == "/"), relativeDepth=\(file.relativePathComponents.count)")
                }
            }
            #endif
            throw FileDeletionError.invalidSelection
        }

        var deletedURLs = Set<URL>()
        var failedFileCount = 0
        for root in roots {
            let matchingFiles = files.filter {
                !deletedURLs.contains($0.url) && Self.contains($0.url, root: root)
            }
            guard !matchingFiles.isEmpty else { continue }
            guard accessibleRoots.contains(root) else {
                failedFileCount += matchingFiles.count
                continue
            }

            for file in matchingFiles where !deletedURLs.contains(file.url) {
                do {
                    try Task.checkCancellation()
                    let coordinator = NSFileCoordinator()
                    var coordinationError: NSError?
                    var deletionError: Error?
                    var didDelete = false
                    coordinator.coordinate(writingItemAt: file.url, options: .forDeleting,
                                           error: &coordinationError) { coordinatedURL in
                        do {
                            try Task.checkCancellation()
                            try fileManager.removeItem(at: coordinatedURL)
                            didDelete = true
                        } catch {
                            deletionError = error
                        }
                    }
                    if let deletionError { throw deletionError }
                    if let coordinationError { throw coordinationError }
                    guard didDelete else { throw FileDeletionError.deletionFailed }
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
    nonisolated static func contains(_ candidate: URL, root: URL) -> Bool {
        guard candidate.isFileURL, root.isFileURL else { return false }
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let candidateComponents = candidate.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard candidateComponents.starts(with: rootComponents) else { return false }
        if candidateComponents.count == rootComponents.count {
            let isDirectory = try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
            return !(isDirectory ?? root.hasDirectoryPath)
        }
        return true
    }
}
