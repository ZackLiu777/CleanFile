//
//  MetadataFileScanner.swift
//  CleanMyIPhone
//

//
//  文件职责：集中定义 MetadataFileScanner 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 定义 `MetadataFileScanner` 的值语义数据与相关行为。
struct MetadataFileScanner: Sendable {
    private let metadataKeys: [URLResourceKey] = [
        .nameKey,
        .isDirectoryKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .typeIdentifierKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey
    ]

    private let fileAccess: any FileAccessProviding
    private let progressInterval: Int

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    nonisolated init(
        fileAccess: any FileAccessProviding = SecurityScopedFileAccess(),
        progressInterval: Int = 50
    ) {
        self.fileAccess = fileAccess
        self.progressInterval = max(1, progressInterval)
    }

    /// 执行 `scan` 分析流程，在遵守文件访问边界的前提下生成结果。
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

    /// 执行 `scanSynchronously` 分析流程，在遵守文件访问边界的前提下生成结果。
    private nonisolated func scanSynchronously(
        directory: URL,
        continuation: AsyncThrowingStream<FileScanEvent, Error>.Continuation
    ) throws -> FileScanResult {
        try Task.checkCancellation()

        return try fileAccess.withAccess(to: directory) {
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var scanResult: Result<FileScanResult, Error>?

            coordinator.coordinate(
                readingItemAt: directory,
                options: [],
                error: &coordinationError
            ) { coordinatedDirectory in
                do {
                    // File Provider may return a coordinated URL different from the
                    // URL selected by the user. All recursive reads use this URL.
                    scanResult = .success(try enumerateDirectory(
                        at: coordinatedDirectory,
                        selectedDirectory: directory,
                        continuation: continuation
                    ))
                } catch {
                    scanResult = .failure(error)
                }
            }

            if let coordinationError {
                throw coordinationError
            }

            guard let scanResult else {
                throw FileScanError.unableToEnumerate
            }

            return try scanResult.get()
        }
    }

    /// 执行 `enumerateDirectory` 分析流程，在遵守文件访问边界的前提下生成结果。
    private nonisolated func enumerateDirectory(
        at directory: URL,
        selectedDirectory: URL,
        continuation: AsyncThrowingStream<FileScanEvent, Error>.Continuation
    ) throws -> FileScanResult {
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard directoryValues.isDirectory == true else {
            throw FileScanError.notDirectory
        }

        var files: [ScannedFile] = []
        var failures: [FileScanFailure] = []
        var scannedFileCount = 0
        var scannedByteCount: Int64 = 0
        var directoryCount = 1
        var maximumDirectoryDepth = 0
        let fileManager = FileManager()

        continuation.yield(.progress(ScanProgress(scannedFileCount: 0, scannedByteCount: 0)))

        // DirectoryEnumerator performs the recursive walk itself. This is
        // important for File Provider URLs: deciding whether to recurse from a
        // single URLResourceValues.isDirectory value can incorrectly flatten a
        // cloud-backed folder when that value is temporarily unavailable.
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: metadataKeys,
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
                relativeTo: directory
            ) else {
                failures.append(FileScanFailure(
                    fileName: url.lastPathComponent,
                    reason: .relativePathUnavailable
                ))
                continue
            }

            do {
                let values = try url.resourceValues(forKeys: Set(metadataKeys))
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
                    url: url,
                    resourceValues: values,
                    relativePathComponents: relativePath
                )
                files.append(file)
                scannedFileCount += 1
                scannedByteCount += file.byteCount

                if scannedFileCount % progressInterval == 0 {
                    continuation.yield(.progress(ScanProgress(
                        scannedFileCount: scannedFileCount,
                        scannedByteCount: scannedByteCount
                    )))
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

        if scannedFileCount % progressInterval != 0 {
            continuation.yield(.progress(ScanProgress(
                scannedFileCount: scannedFileCount,
                scannedByteCount: scannedByteCount
            )))
        }

        let largestFiles = files
            .filter(\.hasKnownByteCount)
            .sorted { $0.byteCount > $1.byteCount }
            .prefix(10)
        let fileTree = FileTreeBuilder.build(rootURL: selectedDirectory, files: files)

        #if DEBUG
        FileTreeDiagnostics.log(fileTree)
        FileScanDiagnostics.log(
            files: files,
            fileTree: fileTree,
            directoryCount: directoryCount,
            maximumDirectoryDepth: maximumDirectoryDepth
        )
        #endif

        return FileScanResult(
            files: files,
            failures: failures,
            summary: StorageSummary(files: files),
            fileTree: fileTree,
            largestFiles: Array(largestFiles)
        )
    }

    /// 判断 `isDirectory` 条件是否成立，供调用方选择正确的处理分支。
    private nonisolated func isDirectory(
        at url: URL,
        resourceValues: URLResourceValues,
        fileManager: FileManager
    ) -> Bool {
        if resourceValues.isDirectory == true {
            return true
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

/// 定义 `FileScanDiagnostics` 使用的有限状态或选项集合。
private enum FileScanDiagnostics: Sendable {
    /// 封装 `log` 对应的局部行为，供当前类型在统一入口下复用。
    nonisolated static func log(
        files: [ScannedFile],
        fileTree: FileNode,
        directoryCount: Int,
        maximumDirectoryDepth: Int
    ) {
        let maximumRelativeDepth = files
            .map(\.relativePathComponents.count)
            .max() ?? 0

        debugPrint("""
        Folder Map Scan Diagnostics
        SCAN files = \(files.count)
        SCAN max relative depth = \(maximumRelativeDepth)
        WALK directories = \(directoryCount)
        WALK max directory depth = \(maximumDirectoryDepth)
        TREE root children = \(fileTree.children.count)
        TREE max depth = \(FileTreeDiagnostics.maximumDepth(of: fileTree))
        """)
    }
}
