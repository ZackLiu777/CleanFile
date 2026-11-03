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
        guard !roots.isEmpty else { throw FileDeletionError.invalidSelection }

        // 根路径只解析一次。按规范路径索引授权，避免 N 个目标与 R 个根逐对解析。
        // 每个目标仍解析符号链接，并且必须先通过整批边界校验才开始删除。
        let active = Set(accessibleRoots)
        var rootAccess: [String: (isDirectory: Bool, accessible: Bool)] = [:]
        for root in roots where root.isFileURL {
            try Task.checkCancellation()
            let resolved = root.resolvingSymlinksInPath().standardizedFileURL
            let isDirectory = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? root.hasDirectoryPath
            let prior = rootAccess[resolved.path]
            rootAccess[resolved.path] = (isDirectory, active.contains(root) || prior?.accessible == true)
        }
        var permittedFiles: [ScannedFile] = []
        var inaccessibleCount = 0
        for file in files {
            try Task.checkCancellation()
            guard file.url.isFileURL else { throw FileDeletionError.invalidSelection }
            var candidate = file.url.resolvingSymlinksInPath().standardizedFileURL
            var isExact = true
            var belongsToRoot = false
            var canAccess = false
            while true {
                if let grant = rootAccess[candidate.path],
                   isExact ? !grant.isDirectory : grant.isDirectory {
                    belongsToRoot = true
                    canAccess = canAccess || grant.accessible
                }
                let parent = candidate.deletingLastPathComponent()
                if parent.path == candidate.path { break }
                candidate = parent
                isExact = false
            }
            guard belongsToRoot else { throw FileDeletionError.invalidSelection }
            if canAccess {
                permittedFiles.append(file)
            } else {
                inaccessibleCount += 1
            }
        }

        var deletedURLs = Set<URL>()
        var failedFileCount = inaccessibleCount
        for file in permittedFiles where !deletedURLs.contains(file.url) {
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
