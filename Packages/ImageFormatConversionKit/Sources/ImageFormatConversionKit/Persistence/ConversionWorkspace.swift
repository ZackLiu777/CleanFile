//
//  文件职责：集中定义 ConversionWorkspace 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import Foundation

/// 定义 `ConversionMediaKind` 使用的有限状态或选项集合。
enum ConversionMediaKind: String, Codable, Sendable {
    case image
    case video
    case audio
}

/// 定义 `PersistedConversionStatus` 使用的有限状态或选项集合。
enum PersistedConversionStatus: String, Codable, Sendable {
    case ready
    case completed
    case failed
    case cancelled
}

/// 定义 `PersistedConversionItem` 的值语义数据与相关行为。
struct PersistedConversionItem: Codable, Sendable {
    let id: UUID
    let sourcePath: String
    let sourceBytes: Int64
    let status: PersistedConversionStatus
    let outputPath: String?
    var sourceKind: AudioSourceKind? = nil
    var duration: TimeInterval? = nil
}

/// 使用 Actor 隔离 `ConversionWorkspace` 的可变状态，确保并发访问安全。
actor ConversionWorkspace {
    static let shared = ConversionWorkspace()

    private let fileManager: FileManager
    private let rootURL: URL
    private let importsURL: URL
    private let manifestsURL: URL
    private let legacyPhotoImportsURL: URL

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(fileManager: FileManager = .default, rootURL customRootURL: URL? = nil) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootURL = customRootURL
            ?? support.appendingPathComponent("Media Conversion Workspace", isDirectory: true)
        importsURL = rootURL.appendingPathComponent("Imports", isDirectory: true)
        manifestsURL = rootURL.appendingPathComponent("Manifests", isDirectory: true)
        legacyPhotoImportsURL = support.appendingPathComponent(
            "Media Conversion Imports",
            isDirectory: true
        )
    }

    /// 封装 `stage` 对应的局部行为，供当前类型在统一入口下复用。
    func stage(
        _ sourceURL: URL,
        id: UUID,
        kind: ConversionMediaKind,
        progress: @escaping @Sendable (Int64, Int64) async -> Void
    ) async throws -> (URL, Int64) {
        try await ConversionImportScheduler.shared.withPermit {
            try await self.stageWithoutScheduling(
                sourceURL,
                id: id,
                kind: kind,
                progress: progress
            )
        }
    }

    /// 封装 `stageWithoutScheduling` 对应的局部行为，供当前类型在统一入口下复用。
    private func stageWithoutScheduling(
        _ sourceURL: URL,
        id: UUID,
        kind: ConversionMediaKind,
        progress: @escaping @Sendable (Int64, Int64) async -> Void
    ) async throws -> (URL, Int64) {
        let source = sourceURL.standardizedFileURL
        var sourceBytes = fileSize(source)
        if isDescendant(source, of: importsURL) {
            await progress(sourceBytes, sourceBytes)
            return (source, sourceBytes)
        }

        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }

        let itemDirectory = importsURL
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        let fileName = source.lastPathComponent.isEmpty ? "source" : source.lastPathComponent
        let destination = itemDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        // PhotosPicker has already created a stable file in our Application
        // Support directory. Moving it into the workspace is atomic on the same
        // volume and avoids reading and writing the full media file a second time.
        if isDescendant(source, of: legacyPhotoImportsURL) {
            do {
                try fileManager.moveItem(at: source, to: destination)
                let movedBytes = fileSize(destination)
                await progress(movedBytes, movedBytes)
                return (destination, movedBytes)
            } catch {
                // Fall back to the streaming copy below if a provider placed the
                // source on a different volume or the atomic move is unavailable.
            }
        }

        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let reader = try FileHandle(forReadingFrom: source)
            let writer = try FileHandle(forWritingTo: destination)
            defer {
                try? reader.close()
                try? writer.close()
            }

            if sourceBytes <= 0 {
                sourceBytes = Int64(try reader.seekToEnd())
                try reader.seek(toOffset: 0)
            }
            var copiedBytes: Int64 = 0
            // Aim for roughly one callback per percentage point. Small files use
            // smaller chunks; very large files stay capped at 1 MiB to avoid
            // excessive I/O calls.
            let targetChunkBytes = sourceBytes > 0 ? sourceBytes / 100 : 1_048_576
            let readChunkBytes = Int(min(max(targetChunkBytes, 16_384), 1_048_576))
            await progress(0, sourceBytes)
            while true {
                try Task.checkCancellation()
                guard let data = try reader.read(upToCount: readChunkBytes), !data.isEmpty else { break }
                try writer.write(contentsOf: data)
                copiedBytes += Int64(data.count)
                await progress(copiedBytes, sourceBytes)
            }
            try writer.synchronize()
        } catch {
            try? fileManager.removeItem(at: itemDirectory)
            throw error
        }

        if isDescendant(source, of: legacyPhotoImportsURL) {
            try? fileManager.removeItem(at: source)
        }
        let stagedBytes = fileSize(destination)
        await progress(stagedBytes, max(sourceBytes, stagedBytes))
        return (destination, stagedBytes)
    }

    /// 加载 `load` 所需的数据，并将结果转换为当前层可消费的状态。
    func load(_ kind: ConversionMediaKind) -> [PersistedConversionItem] {
        let url = manifestURL(kind)
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([PersistedConversionItem].self, from: data)
        else { return [] }
        return records.filter { fileManager.fileExists(atPath: $0.sourcePath) }
    }

    /// 持久化 `save` 对应的数据，并保持后续恢复所需的信息完整。
    func save(_ records: [PersistedConversionItem], kind: ConversionMediaKind) {
        do {
            try fileManager.createDirectory(at: manifestsURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: manifestURL(kind), options: .atomic)
        } catch {
            // Persistence failure must not interrupt an active conversion.
        }
    }

    /// 执行 `delete` 移除流程，并同步更新受影响的业务状态。
    func delete(
        _ record: PersistedConversionItem,
        kind: ConversionMediaKind,
        outputRoot: URL
    ) -> Bool {
        var succeeded = true
        let source = URL(fileURLWithPath: record.sourcePath).standardizedFileURL
        if isDescendant(source, of: importsURL) {
            let itemDirectory = source.deletingLastPathComponent()
            if fileManager.fileExists(atPath: itemDirectory.path) {
                do { try fileManager.removeItem(at: itemDirectory) } catch { succeeded = false }
            }
        }

        if let outputPath = record.outputPath {
            let output = URL(fileURLWithPath: outputPath).standardizedFileURL
            let root = outputRoot.standardizedFileURL
            if isDescendant(output, of: root), fileManager.fileExists(atPath: output.path) {
                do { try fileManager.removeItem(at: output) } catch { succeeded = false }
            }
        }
        return succeeded
    }

    /// 封装 `manifestURL` 对应的局部行为，供当前类型在统一入口下复用。
    private func manifestURL(_ kind: ConversionMediaKind) -> URL {
        manifestsURL.appendingPathComponent("\(kind.rawValue).json")
    }

    /// 计算 `fileSize` 所需的派生值，避免展示层重复实现相同规则。
    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// 判断 `isDescendant` 条件是否成立，供调用方选择正确的处理分支。
    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}
