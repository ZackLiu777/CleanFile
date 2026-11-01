//
//  共享导入收件箱
//
//  供主应用和分享扩展使用，在共享容器中暂存文件及批次清单。
//  清单在文件暂存后才发布；读取时验证文件名，消费后更新清单并清理副本。
//

import Foundation
import UniformTypeIdentifiers

// Compiled into both the app and its share extension. A batch is published only
// after every provider file has been copied into the shared container.
/// 共享容器中的批次暂存协议；清单只引用本批次生成的文件名。
enum ShareImportInbox {
    static let groupID = "group.ZaneLiao.CleanPhone"

    /// 分享入口接受的媒体类别，随清单一起持久化。
    enum Kind: String, Codable { case image, video }

    /// 单个已暂存媒体及其容器内文件名；标识与原始路径无关。
    struct Entry: Codable, Identifiable {
        let id: UUID
        let kind: Kind
        let fileName: String
    }

    /// 同一次导入的清单和创建时间，用于恢复并按顺序处理导入。
    struct Batch: Codable, Identifiable {
        let id: UUID
        let createdAt: Date
        var entries: [Entry]

        var imageCount: Int { entries.filter { $0.kind == .image }.count }
        var videoCount: Int { entries.filter { $0.kind == .video }.count }
    }

    /// 获取并按需创建 App Group 下的导入根目录；容器不可用时抛出错误。
    static func root() throws -> URL {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw CocoaError(.fileNoSuchFile) }
        let directory = group.appendingPathComponent("Share Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 由批次标识构造独立暂存目录，避免不同批次文件相互覆盖。
    static func directory(for id: UUID) throws -> URL {
        try root().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// 读取有效且非空的批次清单，忽略格式错误或目录标识不一致的条目并按创建时间排序。
    static func batches() throws -> [Batch] {
        let rootURL = try root()
        return try FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent),
                  let data = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
                  let batch = try? JSONDecoder().decode(Batch.self, from: data),
                  batch.id == id, !batch.entries.isEmpty else { return nil }
            return batch
        }.sorted { $0.createdAt < $1.createdAt }
    }

    /// 验证清单文件名不是隐藏项或路径，然后在对应批次目录内构造 URL。
    static func fileURL(for entry: Entry, in batch: Batch) throws -> URL {
        guard !entry.fileName.isEmpty,
              !entry.fileName.hasPrefix("."),
              URL(fileURLWithPath: entry.fileName).lastPathComponent == entry.fileName,
              !entry.fileName.contains("/") else { throw CocoaError(.fileReadInvalidFileName) }
        return try directory(for: batch.id).appendingPathComponent(entry.fileName)
    }

    // "Copy to Filevra" delivers file URLs to the app, unlike an Action Extension.
    // Stage them before the system revokes access to the incoming URLs.
    /// 以最多三个并行任务暂存输入文件，按原输入顺序生成清单。
    /// 所有可用文件暂存完成后才原子写入清单；没有成功项时清理目录并抛错。
    static func importDocumentURLs(_ urls: [URL]) async throws -> Batch {
        let batchID = UUID()
        let directory = try directory(for: batchID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var staged: [(Int, Entry)] = []
        await withTaskGroup(of: (Int, Entry?).self) { group in
            var nextIndex = 0
            for _ in 0..<min(3, urls.count) {
                let index = nextIndex
                group.addTask { (index, stageDocument(urls[index], in: directory)) }
                nextIndex += 1
            }
            for await result in group {
                if let entry = result.1 { staged.append((result.0, entry)) }
                if nextIndex < urls.count {
                    let index = nextIndex
                    group.addTask { (index, stageDocument(urls[index], in: directory)) }
                    nextIndex += 1
                }
            }
        }
        let entries = staged.sorted { $0.0 < $1.0 }.map(\.1)
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: directory)
            throw CocoaError(.fileReadUnknown)
        }
        let batch = Batch(id: batchID, createdAt: Date(), entries: entries)
        try JSONEncoder().encode(batch).write(
            to: directory.appendingPathComponent("manifest.json"), options: .atomic
        )
        return batch
    }

    /// 仅复制受支持的图片和视频类型，并在复制期间持有可用的安全作用域。
    /// 失败时清理该项的不完整副本，返回 nil 以允许其他项目继续。
    nonisolated private static func stageDocument(_ source: URL, in directory: URL) -> Entry? {
        guard source.isFileURL,
              let type = UTType(filenameExtension: source.pathExtension),
              let ext = type.preferredFilenameExtension?.lowercased() else { return nil }
        let kind: Kind
        if type.conforms(to: .movie), ["mov", "mp4", "m4v"].contains(ext) {
            kind = .video
        } else if type.conforms(to: .image),
                  ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"].contains(ext) {
            kind = .image
        } else {
            return nil
        }
        let entry = Entry(id: UUID(), kind: kind, fileName: "\(UUID().uuidString).\(ext)")
        let destination = directory.appendingPathComponent(entry.fileName)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return entry
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }

    /// 消费指定条目；剩余清单先原子发布再删除对应副本，全部消费时移除批次目录。
    static func remove(_ ids: Set<UUID>, from batch: Batch) throws {
        let directory = try directory(for: batch.id)
        var remaining = batch
        remaining.entries.removeAll { ids.contains($0.id) }
        if remaining.entries.isEmpty {
            try FileManager.default.removeItem(at: directory)
        } else {
            // Publish the reduced manifest before deleting consumed copies.
            try JSONEncoder().encode(remaining).write(
                to: directory.appendingPathComponent("manifest.json"), options: .atomic
            )
            for entry in batch.entries where ids.contains(entry.id) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.fileName))
            }
        }
    }
}
