//
//  维护转换工作区中的导入副本、各媒体类型清单及恢复所需状态。
//  导入优先复用安全的本地副本或移动临时文件，否则分块复制并支持取消。
//  清理限制在指定目录内；删除输出失败时保留源副本，便于恢复和重试。
//  各媒体状态对象使用工作区暂存输入、保存清单，并在恢复时过滤不可用来源。
//  工作区管理其受限范围内的副本与输出；实际照片原件替换由单独服务处理。
//

import Foundation

/// 工作区按媒体种类划分导入文件和清单。
enum ConversionMediaKind: String, Codable, Hashable, Sendable {
    case image
    case video
    case audio
}

/// 跨启动恢复所需的稳定状态；运行中的任务恢复为 ready。
enum PersistedConversionStatus: String, Codable, Sendable {
    case ready
    case completed
    case failed
    case cancelled
}

/// The persistence representation of a runtime conversion status.
/// Runtime enums remain free to model media-specific states while manifests
/// consume one stable shape.
struct PersistedConversionState {
    let status: PersistedConversionStatus
    let outputPath: String?
}

/// 将媒体专属运行状态转换为清单可保存的共同表示。
protocol ConversionStatusPersistable {
    var persistedState: PersistedConversionState { get }
}

/// 将图片转换状态映射为可持久化状态，并在恢复时重建对应值。
extension ImageConversionItemStatus: ConversionStatusPersistable {
    var persistedState: PersistedConversionState {
        switch self {
        case let .completed(outputURL):
            PersistedConversionState(status: .completed, outputPath: outputURL.path)
        case .failed:
            PersistedConversionState(status: .failed, outputPath: nil)
        case .cancelled:
            PersistedConversionState(status: .cancelled, outputPath: nil)
        case .inspecting, .ready, .converting:
            PersistedConversionState(status: .ready, outputPath: nil)
        }
    }
}

/// 将音频转换状态映射为可持久化状态，并在恢复时重建对应值。
extension AudioConversionStatus: ConversionStatusPersistable {
    var persistedState: PersistedConversionState {
        switch self {
        case let .completed(outputURL):
            PersistedConversionState(status: .completed, outputPath: outputURL.path)
        case .failed:
            PersistedConversionState(status: .failed, outputPath: nil)
        case .cancelled:
            PersistedConversionState(status: .cancelled, outputPath: nil)
        case .ready, .converting:
            PersistedConversionState(status: .ready, outputPath: nil)
        }
    }
}

/// 将视频转换状态映射为可持久化状态，并在恢复时重建对应值。
extension VideoConversionStatus: ConversionStatusPersistable {
    var persistedState: PersistedConversionState {
        switch self {
        case let .completed(outputURL):
            PersistedConversionState(status: .completed, outputPath: outputURL.path)
        case .failed:
            PersistedConversionState(status: .failed, outputPath: nil)
        case .cancelled:
            PersistedConversionState(status: .cancelled, outputPath: nil)
        case .ready, .converting:
            PersistedConversionState(status: .ready, outputPath: nil)
        }
    }
}

/// Owns the filesystem naming convention for converted media directories.
enum ConversionOutputDirectory {
    /// 获取对应输出目录路径；无法取得文稿目录时使用临时目录。
    static func url(for kind: ConversionMediaKind, fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent(name(for: kind), isDirectory: true)
    }

    /// 保持各媒体输出目录名称与已有文件兼容。
    private static func name(for kind: ConversionMediaKind) -> String {
        switch kind {
        case .image: "Converted Images"
        case .video: "Converted Videos"
        case .audio: "Converted Audio"
        }
    }
}

/// 保存一项转换的源路径、状态、可选输出路径及恢复所需元数据。
struct PersistedConversionItem: Codable, Sendable {
    let id: UUID
    let sourcePath: String
    let sourceBytes: Int64
    let status: PersistedConversionStatus
    let outputPath: String?
    /// The Photos asset that produced the staged copy. Nil for Files imports
    /// and legacy records created before source tracking was introduced.
    var photoAssetIdentifier: String? = nil
    var sourceKind: AudioSourceKind? = nil
    var duration: TimeInterval? = nil
    var sampleRate: Double? = nil
    var channelCount: Int? = nil
}

/// 隔离工作区文件与清单操作，并限制导入和清理的路径范围。
actor ConversionWorkspace {
    static let shared = ConversionWorkspace()

    private let fileManager: FileManager
    private let rootURL: URL
    private let importsURL: URL
    private let manifestsURL: URL
    private let legacyPhotoImportsURL: URL
    private let sharedImportsURL: URL?

    /// 使用指定文件管理器和可选根目录配置导入、清单及旧目录位置。
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
        sharedImportsURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.ZaneLiao.CleanPhone"
        )?.appendingPathComponent("Share Imports", isDirectory: true)
    }

    /// 经共享导入调度器取得许可后，将源文件暂存到工作区并报告字节进度。
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

    /// 复用已有暂存文件，或选择复制、移动和分块读取路径。
    /// 分块复制期间检查取消，失败时清理该项目录并传播错误。
    private func stageWithoutScheduling(
        _ sourceURL: URL,
        id: UUID,
        kind: ConversionMediaKind,
        progress: @escaping @Sendable (Int64, Int64) async -> Void
    ) async throws -> (URL, Int64) {
        let performanceID = ConversionPerformance.begin("Conversion Import Stage")
        defer { ConversionPerformance.end("Conversion Import Stage", id: performanceID) }
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

        // Shared-import files remain available for retry until the app has
        // staged them. A filesystem copy can use the volume's copy-on-write
        // optimization, avoiding a second byte-by-byte pass over large videos.
        if let sharedImportsURL, isDescendant(source, of: sharedImportsURL) {
            do {
                try fileManager.copyItem(at: source, to: destination)
                let copiedBytes = fileSize(destination)
                guard copiedBytes == sourceBytes else { throw CocoaError(.fileReadCorruptFile) }
                await progress(copiedBytes, copiedBytes)
                return (destination, copiedBytes)
            } catch {
                try? fileManager.removeItem(at: destination)
                // Fall back to the streaming path when cloning is unavailable.
            }
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

    /// 读取媒体清单并过滤源文件已不存在的记录；缺失或损坏的清单返回空数组。
    func load(_ kind: ConversionMediaKind) -> [PersistedConversionItem] {
        let performanceID = ConversionPerformance.begin("Conversion Manifest Load")
        defer { ConversionPerformance.end("Conversion Manifest Load", id: performanceID) }
        let url = manifestURL(kind)
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([PersistedConversionItem].self, from: data)
        else { return [] }
        return records.filter { fileManager.fileExists(atPath: $0.sourcePath) }
    }

    /// 原子写入媒体清单；持久化失败不会中断正在进行的转换。
    func save(_ records: [PersistedConversionItem], kind: ConversionMediaKind) {
        let performanceID = ConversionPerformance.begin("Conversion Manifest Save")
        defer { ConversionPerformance.end("Conversion Manifest Save", id: performanceID) }
        do {
            try fileManager.createDirectory(at: manifestsURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: manifestURL(kind), options: .atomic)
        } catch {
            // Persistence failure must not interrupt an active conversion.
        }
    }

    /// 仅删除指定输出根目录内的输出及工作区内的暂存源。
    /// 输出删除失败时保留源并返回 false，以便调用方保留记录和重试。
    func delete(
        _ record: PersistedConversionItem,
        kind: ConversionMediaKind,
        outputRoot: URL
    ) -> Bool {
        var succeeded = true
        let source = URL(fileURLWithPath: record.sourcePath).standardizedFileURL
        if let outputPath = record.outputPath {
            let output = URL(fileURLWithPath: outputPath).standardizedFileURL
            let root = outputRoot.standardizedFileURL
            if isDescendant(output, of: root), fileManager.fileExists(atPath: output.path) {
                do { try fileManager.removeItem(at: output) } catch { succeeded = false }
            }
        }
        // Keep the staged source when output removal fails so the manifest can
        // still restore this item and the user can retry the cleanup.
        guard succeeded else { return false }
        if isDescendant(source, of: importsURL) {
            let itemDirectory = source.deletingLastPathComponent()
            if fileManager.fileExists(atPath: itemDirectory.path) {
                do { try fileManager.removeItem(at: itemDirectory) } catch { succeeded = false }
            }
        }
        return succeeded
    }

    /// 顺序清理多条记录，返回实际成功的 ID，允许调用方保留失败项。
    func delete(
        _ records: [PersistedConversionItem],
        kind: ConversionMediaKind,
        outputRoot: URL
    ) -> Set<UUID> {
        var deletedIDs = Set<UUID>()
        for record in records where delete(record, kind: kind, outputRoot: outputRoot) {
            deletedIDs.insert(record.id)
        }
        return deletedIDs
    }

    /// 按媒体种类生成独立的 JSON 清单路径。
    private func manifestURL(_ kind: ConversionMediaKind) -> URL {
        manifestsURL.appendingPathComponent("\(kind.rawValue).json")
    }

    /// 获取文件大小；元数据不可用时返回零。
    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// 按标准化路径组件检查严格子路径，避免字符串前缀造成目录误判。
    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}
