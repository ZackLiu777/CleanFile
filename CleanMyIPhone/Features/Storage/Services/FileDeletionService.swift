//
//  授权范围内的文件删除
//
//  协调用户选中的根目录授权、路径边界校验及逐文件删除。
//  单项失败计数并继续，取消则抛出；符号链接解析后仍须位于授权边界内。
//

//
//  FileDeletionService.swift
//  CleanMyIPhone
//

//
//  文件职责：封装 FileDeletion 领域服务及其边界处理。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 管理显式触发的删除操作；只允许处理属于所选根目录的文件，并返回逐项执行结果。
actor FileDeletionService {
    private let fileManager = FileManager.default

    /// 单根目录的便利入口，将同一删除语义委托给多根目录实现。
    func delete(
        files: [ScannedFile],
        selectedRoot: URL
    ) throws -> FileDeletionResult {
        try delete(files: files, selectedRoots: [selectedRoot])
    }

    /// 保留原始授权 URL 并校验每个目标，随后通过文件协调器逐项删除。
    /// 目标不属于所选根目录时拒绝整批；单个目标无法访问或删除失败则计入失败数并继续。
    /// 取消会立即向上抛出，已经成功删除的文件不会在此处恢复。
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

    /// 解析符号链接并按路径组件检查目标是否落在根目录内，避免字符串前缀造成越界。
    /// 根本身只有在其不是目录时才被视作可删除目标。
    nonisolated static func contains(_ candidate: URL, root: URL) -> Bool {
        guard candidate.isFileURL, root.isFileURL else { return false }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootComponents = resolvedRoot.pathComponents
        let candidateComponents = candidate.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard candidateComponents.starts(with: rootComponents) else { return false }
        if candidateComponents.count == rootComponents.count {
            // The selected URL may describe a link, whose metadata is not the target's type.
            let isDirectory = try? resolvedRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
            return !(isDirectory ?? root.hasDirectoryPath)
        }
        return true
    }
}
