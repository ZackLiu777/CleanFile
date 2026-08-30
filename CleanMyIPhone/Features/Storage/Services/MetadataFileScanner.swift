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

/// 定义 `MetadataFileScanner` 的值语义数据与相关行为。
struct MetadataFileScanner: Sendable {
    private nonisolated static let metadataKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .fileSizeKey,
        .typeIdentifierKey
    ]

    private let fileAccess: any FileAccessProviding
    private let progressInterval: Int
    private let metadataKeySet: Set<URLResourceKey>

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

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    nonisolated init(
        fileAccess: any FileAccessProviding = SecurityScopedFileAccess(),
        progressInterval: Int = 50
    ) {
        self.fileAccess = fileAccess
        self.progressInterval = max(1, progressInterval)
        metadataKeySet = Set(Self.metadataKeys)
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
            var enumerationResult: Result<DirectoryEnumeration, Error>?

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
                        continuation: continuation
                    ))
                } catch {
                    enumerationResult = .failure(error)
                }
            }

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

            return FileScanResult(
                files: enumeration.files,
                failures: enumeration.failures,
                summary: enumeration.summaryAccumulator.makeSummary(),
                fileTree: fileTree,
                largestFiles: enumeration.largestFilesAccumulator.sortedDescending()
            )
        }
    }

    /// 执行 `enumerateDirectory` 分析流程，在遵守文件访问边界的前提下生成结果。
    private nonisolated func enumerateDirectory(
        at directory: URL,
        selectedDirectory: URL,
        continuation: AsyncThrowingStream<FileScanEvent, Error>.Continuation
    ) throws -> DirectoryEnumeration {
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
        var maximumRelativeDepth = 0
        var lastReportedFileCount = 0
        var lastProgressUptime = DispatchTime.now().uptimeNanoseconds
        var summaryAccumulator = StorageSummaryAccumulator()
        var treeAccumulator = FileTreeAccumulator(rootURL: selectedDirectory)
        var largestFilesAccumulator = LargestFilesAccumulator(limit: 10)
        let fileManager = FileManager()
        let rootComponents = directory.pathComponents

        continuation.yield(.progress(ScanProgress(scannedFileCount: 0, scannedByteCount: 0)))

        // DirectoryEnumerator performs the recursive walk itself. This is
        // important for File Provider URLs: deciding whether to recurse from a
        // single URLResourceValues.isDirectory value can incorrectly flatten a
        // cloud-backed folder when that value is temporarily unavailable.
        guard let enumerator = fileManager.enumerator(
            at: directory,
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
                    url: url,
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
                            scannedFileCount: scannedFileCount,
                            scannedByteCount: scannedByteCount
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
                scannedFileCount: scannedFileCount,
                scannedByteCount: scannedByteCount
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

    /// 判断 `isDirectory` 条件是否成立，供调用方选择正确的处理分支。
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

/// 定义 `FileScanDiagnostics` 使用的有限状态或选项集合。
private enum FileScanDiagnostics: Sendable {
    /// 封装 `log` 对应的局部行为，供当前类型在统一入口下复用。
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
