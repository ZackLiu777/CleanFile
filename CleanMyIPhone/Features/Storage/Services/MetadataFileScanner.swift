//
//  基于元数据的文件扫描
//
//  在后台枚举用户选择的来源，流式报告进度并构造汇总和文件树。
//  扫描只读取必要元数据；各来源独立获取访问权限，失败和取消通过结果或错误表达。
//

//
//  MetadataFileScanner.swift
//  CleanMyIPhone
//

//
//  文件职责：集中定义 MetadataFileScanner 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import Dispatch
import Foundation

/// 基于必要元数据扫描用户所选来源，并通过异步流报告进度、失败和最终结果。
struct MetadataFileScanner: Sendable {
    // Type identifiers are intentionally omitted from the recursive walk.
    // File Provider may need an additional metadata round-trip to resolve them;
    // extension-based classification is sufficient for the storage overview.
    private nonisolated static let metadataKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .fileSizeKey
    ]

    private let fileAccess: any FileAccessProviding
    private let progressInterval: Int
    private let metadataKeySet: Set<URLResourceKey>

    /// 保存一次目录遍历累积的文件、失败与统计；完成协调读取后再生成最终展示结构。
    private struct DirectoryEnumeration: Sendable {
        let files: [ScannedFile]
        let failures: [FileScanFailure]
        let summaryAccumulator: StorageSummaryAccumulator
        let treeAccumulator: FileTreeAccumulator
        let largestFilesAccumulator: LargestFilesAccumulator
        let directoryCount: Int
        let maximumDirectoryDepth: Int
        let maximumRelativeDepth: Int
    }

    /// 注入文件访问策略并限制进度间隔至少为一，便于不同来源共享扫描流程。
    nonisolated init(
        fileAccess: any FileAccessProviding = SecurityScopedFileAccess(),
        progressInterval: Int = 50
    ) {
        self.fileAccess = fileAccess
        self.progressInterval = max(1, progressInterval)
        metadataKeySet = Set(Self.metadataKeys)
    }

    /// 在独立任务扫描一个目录并发送进度与结果；消费端终止时取消后台任务。
    nonisolated func scan(directory: URL) -> AsyncThrowingStream<FileScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    let result = try self.scanSynchronously(
                        directory: directory,
                        continuation: continuation
                    )
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: FileScanError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    /// Scans an explicit collection selected by the user. Each source keeps an
    /// independent security scope so File Provider locations are never assumed
    /// to share a common root. Sources are processed serially to avoid forcing
    /// several cloud providers to hydrate content at the same time.
    /// 串行扫描多个独立授权来源，通过流返回合并进度和结果，避免并发触发多个云端提供方。
    nonisolated func scan(sources: [URL]) -> AsyncThrowingStream<FileScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    let result = try self.scanSourcesSynchronously(
                        sources: sources,
                        continuation: continuation
                    )
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: FileScanError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    /// 逐个处理文件或目录来源，按标准化 URL 去重并为多来源构造虚拟根。
    /// 单个来源不可访问时记录失败继续，其余来源仍可生成汇总。
    private nonisolated func scanSourcesSynchronously(
        sources: [URL],
        continuation: AsyncThrowingStream<FileScanEvent, Error>.Continuation
    ) throws -> FileScanResult {
        guard !sources.isEmpty else { throw FileScanError.selectionFailed }

        var files: [ScannedFile] = []
        var failures: [FileScanFailure] = []
        var seenURLs = Set<URL>()
        var scannedByteCount: Int64 = 0

        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            do {
                let sourceFiles: [ScannedFile]
                let sourceIsDirectory = try isDirectorySource(source)
                if sourceIsDirectory {
                    let directoryResult = try scanSynchronously(
                        directory: source,
                        continuation: continuation,
                        progressOffset: files.count,
                        progressByteOffset: scannedByteCount
                    )
                    sourceFiles = directoryResult.files
                    failures.append(contentsOf: directoryResult.failures)
                } else {
                    sourceFiles = [try scanSingleFile(source)]
                }

                let sourceName = source.lastPathComponent.isEmpty
                    ? String(index + 1)
                    : source.lastPathComponent
                let uniqueSourceName = sources.count > 1
                    ? "\(sourceName) · \(index + 1)"
                    : sourceName

                for file in sourceFiles {
                    let normalizedURL = file.url.standardizedFileURL
                    guard seenURLs.insert(normalizedURL).inserted else { continue }
                    let relativeComponents = sourceIsDirectory
                        ? [uniqueSourceName] + file.relativePathComponents
                        : [uniqueSourceName]
                    let scopedFile = ScannedFile(
                        url: file.url,
                        name: file.name,
                        relativePathComponents: relativeComponents,
                        category: file.category,
                        byteCount: file.byteCount,
                        hasKnownByteCount: file.hasKnownByteCount,
                        creationDate: file.creationDate,
                        modificationDate: file.modificationDate
                    )
                    files.append(scopedFile)
                    if scopedFile.hasKnownByteCount { scannedByteCount += scopedFile.byteCount }
                }

                continuation.yield(.progress(ScanProgress(
                    scannedFileCount: files.count,
                    scannedByteCount: scannedByteCount
                )))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(FileScanFailure(
                    fileName: source.lastPathComponent,
                    reason: .inaccessible
                ))
            }
        }

        let virtualRoot = URL(fileURLWithPath: "/Selected Sources", isDirectory: true)
        var summaryAccumulator = StorageSummaryAccumulator()
        var treeAccumulator = FileTreeAccumulator(rootURL: virtualRoot)
        var largestAccumulator = LargestFilesAccumulator(limit: 10)
        for file in files {
            summaryAccumulator.append(file)
            treeAccumulator.append(file)
            largestAccumulator.append(file)
        }

        return FileScanResult(
            files: files,
            failures: failures,
            summary: summaryAccumulator.makeSummary(),
            fileTree: treeAccumulator.makeTree(),
            largestFiles: largestAccumulator.sortedDescending()
        )
    }

    /// 在所选文件的访问作用域内读取大小和类型所需元数据，不读取文件内容。
    private nonisolated func scanSingleFile(_ file: URL) throws -> ScannedFile {
        try fileAccess.withAccess(to: file) {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: metadataKeySet)
            guard values.isDirectory != true else { throw FileScanError.notDirectory }
            return ScannedFile(
                url: file,
                name: file.lastPathComponent,
                relativePathComponents: [file.lastPathComponent],
                category: FileCategory.classify(fileExtension: file.pathExtension),
                byteCount: Int64(values.fileSize ?? 0),
                hasKnownByteCount: values.fileSize != nil
            )
        }
    }

    /// 在授权范围内解析来源并判断是否为目录；元数据缺失时使用 URL 的目录提示。
    private nonisolated func isDirectorySource(_ source: URL) throws -> Bool {
        try fileAccess.withAccess(to: source) {
            try Task.checkCancellation()
            let values = try source.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
            if let isDirectory = values.isDirectory { return isDirectory }
            return source.hasDirectoryPath
        }
    }

    /// 在安全作用域和文件协调读取期间遍历目录，协调结束后再完成树与汇总。
    /// File Provider 返回的协调 URL 仅用于本次读取，后续访问仍基于用户选择的根。
    private nonisolated func scanSynchronously(
        directory: URL,
        continuation: AsyncThrowingStream<FileScanEvent, Error>.Continuation,
        progressOffset: Int = 0,
        progressByteOffset: Int64 = 0
    ) throws -> FileScanResult {
        try Task.checkCancellation()

        return try fileAccess.withAccess(to: directory) {
            // Security-scoped and File Provider access can block. Re-check as
            // soon as access is acquired so a cancelled consumer cannot start
            // coordination or enumeration afterward.
            try Task.checkCancellation()

            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var enumerationResult: Result<DirectoryEnumeration, Error>?

            let enumerationInterval = StoragePerformance.begin("Storage Directory Enumerate")
            coordinator.coordinate(
                readingItemAt: directory,
                options: [],
                error: &coordinationError
            ) { coordinatedDirectory in
                do {
                    // File Provider may return a coordinated URL different from the
                    // URL selected by the user. All recursive reads use this URL.
                    enumerationResult = .success(try enumerateDirectory(
                        at: coordinatedDirectory,
                        selectedDirectory: directory,
                        continuation: continuation,
                        progressOffset: progressOffset,
                        progressByteOffset: progressByteOffset
                    ))
                } catch {
                    enumerationResult = .failure(error)
                }
            }
            StoragePerformance.end("Storage Directory Enumerate", id: enumerationInterval)

            if let coordinationError {
                throw coordinationError
            }

            guard let enumerationResult else {
                throw FileScanError.unableToEnumerate
            }

            // CPU-only aggregation is deliberately finalized after coordinated
            // file access has ended, so a provider is not held while sorting
            // hierarchy nodes or producing diagnostics.
            let enumeration = try enumerationResult.get()
            let finalizeInterval = StoragePerformance.begin("Storage Scan Finalize")
            let fileTree = enumeration.treeAccumulator.makeTree()

            #if DEBUG
            FileScanDiagnostics.log(
                fileCount: enumeration.files.count,
                fileTree: fileTree,
                directoryCount: enumeration.directoryCount,
                maximumDirectoryDepth: enumeration.maximumDirectoryDepth,
                maximumRelativeDepth: enumeration.maximumRelativeDepth
            )
            #endif

            let result = FileScanResult(
                files: enumeration.files,
                failures: enumeration.failures,
                summary: enumeration.summaryAccumulator.makeSummary(),
                fileTree: fileTree,
                largestFiles: enumeration.largestFilesAccumulator.sortedDescending()
            )
            StoragePerformance.end("Storage Scan Finalize", id: finalizeInterval)
            return result
        }
    }

    /// 递归读取文件的必要元数据并增量更新统计、树和最大文件候选。
    /// 按数量与时间节流进度，记录不可访问项，周期性检查取消。
    private nonisolated func enumerateDirectory(
        at directory: URL,
        selectedDirectory: URL,
        continuation: AsyncThrowingStream<FileScanEvent, Error>.Continuation,
        progressOffset: Int,
        progressByteOffset: Int64
    ) throws -> DirectoryEnumeration {
        // Resolve only the selected/coordinated root, while its access grant is active.
        // Enumeration and relative paths must share this namespace; emitted URLs
        // are still reconstructed under selectedDirectory for subsequent scoped access.
        let enumerationDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let directoryValues = try enumerationDirectory.resourceValues(forKeys: [.isDirectoryKey])
        guard directoryValues.isDirectory == true else {
            throw FileScanError.notDirectory
        }

        var files: [ScannedFile] = []
        var failures: [FileScanFailure] = []
        var scannedFileCount = 0
        var scannedByteCount: Int64 = 0
        var directoryCount = 1
        var maximumDirectoryDepth = 0
        var maximumRelativeDepth = 0
        var lastReportedFileCount = 0
        var lastProgressUptime = DispatchTime.now().uptimeNanoseconds
        var summaryAccumulator = StorageSummaryAccumulator()
        var treeAccumulator = FileTreeAccumulator(rootURL: selectedDirectory)
        var largestFilesAccumulator = LargestFilesAccumulator(limit: 10)
        let fileManager = FileManager()
        let rootComponents = enumerationDirectory.pathComponents

        continuation.yield(.progress(ScanProgress(
            scannedFileCount: progressOffset,
            scannedByteCount: progressByteOffset
        )))

        // DirectoryEnumerator performs the recursive walk itself. This is
        // important for File Provider URLs: deciding whether to recurse from a
        // single URLResourceValues.isDirectory value can incorrectly flatten a
        // cloud-backed folder when that value is temporarily unavailable.
        guard let enumerator = fileManager.enumerator(
            at: enumerationDirectory,
            includingPropertiesForKeys: Self.metadataKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { url, _ in
                failures.append(FileScanFailure(
                    fileName: url.lastPathComponent,
                    reason: .inaccessible
                ))
                return true
            }
        ) else {
            throw FileScanError.unableToEnumerate
        }

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()

            guard let relativePath = RelativePathComponents.make(
                fileURL: url,
                rootComponents: rootComponents
            ) else {
                failures.append(FileScanFailure(
                    fileName: url.lastPathComponent,
                    reason: .relativePathUnavailable
                ))
                continue
            }

            do {
                let values = try url.resourceValues(forKeys: metadataKeySet)
                let isDirectory = isDirectory(
                    at: url,
                    resourceValues: values,
                    fileManager: fileManager
                )

                if isDirectory {
                    directoryCount += 1
                    maximumDirectoryDepth = max(
                        maximumDirectoryDepth,
                        relativePath.count
                    )
                    continue
                }

                let file = ScannedFile(
                    // Coordinated URLs belong to this read operation. Retain the
                    // selected root's namespace for later scoped operations.
                    url: relativePath.reduce(selectedDirectory) {
                        $0.appendingPathComponent($1)
                    },
                    resourceValues: values,
                    relativePathComponents: relativePath
                )
                files.append(file)
                summaryAccumulator.append(file)
                treeAccumulator.append(file)
                largestFilesAccumulator.append(file)
                scannedFileCount += 1
                scannedByteCount += file.byteCount
                maximumRelativeDepth = max(maximumRelativeDepth, relativePath.count)

                if scannedFileCount % progressInterval == 0 {
                    let currentUptime = DispatchTime.now().uptimeNanoseconds
                    if currentUptime - lastProgressUptime >= 100_000_000 {
                        continuation.yield(.progress(ScanProgress(
                            scannedFileCount: progressOffset + scannedFileCount,
                            scannedByteCount: progressByteOffset + scannedByteCount
                        )))
                        lastReportedFileCount = scannedFileCount
                        lastProgressUptime = currentUptime
                    }
                }
            } catch let reason as FileScanFailureReason {
                failures.append(FileScanFailure(
                    fileName: url.lastPathComponent,
                    reason: reason
                ))
            } catch {
                failures.append(FileScanFailure(
                    fileName: url.lastPathComponent,
                    reason: .inaccessible
                ))
            }
        }

        if lastReportedFileCount != scannedFileCount {
            continuation.yield(.progress(ScanProgress(
                scannedFileCount: progressOffset + scannedFileCount,
                scannedByteCount: progressByteOffset + scannedByteCount
            )))
        }

        return DirectoryEnumeration(
            files: files,
            failures: failures,
            summaryAccumulator: summaryAccumulator,
            treeAccumulator: treeAccumulator,
            largestFilesAccumulator: largestFilesAccumulator,
            directoryCount: directoryCount,
            maximumDirectoryDepth: maximumDirectoryDepth,
            maximumRelativeDepth: maximumRelativeDepth
        )
    }

    /// 优先使用资源元数据判断目录，缺失时回退到文件系统查询和 URL 提示。
    private nonisolated func isDirectory(
        at url: URL,
        resourceValues: URLResourceValues,
        fileManager: FileManager
    ) -> Bool {
        if let isDirectory = resourceValues.isDirectory {
            return isDirectory
        }

        var directoryFlag = ObjCBool(false)
        if fileManager.fileExists(atPath: url.path, isDirectory: &directoryFlag) {
            return directoryFlag.boolValue
        }

        // Some providers omit both metadata and a local filesystem result, but
        // preserve the directory URL flag while exposing the item.
        return url.hasDirectoryPath
    }
}

/// 汇总扫描结构诊断，避免将文件名或完整路径写入日志。
private enum FileScanDiagnostics: Sendable {
    /// 仅输出文件数和目录层级等聚合信息，不记录文件名或路径。
    nonisolated static func log(
        fileCount: Int,
        fileTree: FileNode,
        directoryCount: Int,
        maximumDirectoryDepth: Int,
        maximumRelativeDepth: Int
    ) {
        debugPrint("""
        Folder Map Scan Diagnostics
        SCAN files = \(fileCount)
        SCAN max relative depth = \(maximumRelativeDepth)
        WALK directories = \(directoryCount)
        WALK max directory depth = \(maximumDirectoryDepth)
        TREE root children = \(fileTree.children.count)
        """)
    }
}
