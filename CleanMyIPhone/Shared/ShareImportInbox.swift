import Foundation
import UniformTypeIdentifiers

// Compiled into both the app and its share extension. A batch is published only
// after every provider file has been copied into the shared container.
enum ShareImportInbox {
    static let groupID = "group.ZaneLiao.CleanPhone"

    enum Kind: String, Codable { case image, video }

    struct Entry: Codable, Identifiable {
        let id: UUID
        let kind: Kind
        let fileName: String
    }

    struct Batch: Codable, Identifiable {
        let id: UUID
        let createdAt: Date
        var entries: [Entry]

        var imageCount: Int { entries.filter { $0.kind == .image }.count }
        var videoCount: Int { entries.filter { $0.kind == .video }.count }
    }

    static func root() throws -> URL {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw CocoaError(.fileNoSuchFile) }
        let directory = group.appendingPathComponent("Share Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func directory(for id: UUID) throws -> URL {
        try root().appendingPathComponent(id.uuidString, isDirectory: true)
    }

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

    static func fileURL(for entry: Entry, in batch: Batch) throws -> URL {
        guard !entry.fileName.isEmpty,
              !entry.fileName.hasPrefix("."),
              URL(fileURLWithPath: entry.fileName).lastPathComponent == entry.fileName,
              !entry.fileName.contains("/") else { throw CocoaError(.fileReadInvalidFileName) }
        return try directory(for: batch.id).appendingPathComponent(entry.fileName)
    }

    // "Copy to Filevra" delivers file URLs to the app, unlike an Action Extension.
    // Stage them before the system revokes access to the incoming URLs.
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
