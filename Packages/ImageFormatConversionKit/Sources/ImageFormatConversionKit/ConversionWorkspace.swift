import Foundation

enum ConversionMediaKind: String, Codable, Sendable {
    case image
    case video
    case audio
}

enum PersistedConversionStatus: String, Codable, Sendable {
    case ready
    case completed
    case failed
    case cancelled
}

struct PersistedConversionItem: Codable, Sendable {
    let id: UUID
    let sourcePath: String
    let sourceBytes: Int64
    let status: PersistedConversionStatus
    let outputPath: String?
}

actor ConversionWorkspace {
    static let shared = ConversionWorkspace()

    private let fileManager: FileManager
    private let rootURL: URL
    private let importsURL: URL
    private let manifestsURL: URL
    private let legacyPhotoImportsURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootURL = support.appendingPathComponent("Media Conversion Workspace", isDirectory: true)
        importsURL = rootURL.appendingPathComponent("Imports", isDirectory: true)
        manifestsURL = rootURL.appendingPathComponent("Manifests", isDirectory: true)
        legacyPhotoImportsURL = support.appendingPathComponent(
            "Media Conversion Imports",
            isDirectory: true
        )
    }

    func stage(_ sourceURL: URL, id: UUID, kind: ConversionMediaKind) throws -> (URL, Int64) {
        let source = sourceURL.standardizedFileURL
        if isDescendant(source, of: importsURL) {
            return (source, fileSize(source))
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
        try fileManager.copyItem(at: source, to: destination)
        if isDescendant(source, of: legacyPhotoImportsURL) {
            try? fileManager.removeItem(at: source)
        }
        return (destination, fileSize(destination))
    }

    func load(_ kind: ConversionMediaKind) -> [PersistedConversionItem] {
        let url = manifestURL(kind)
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([PersistedConversionItem].self, from: data)
        else { return [] }
        return records.filter { fileManager.fileExists(atPath: $0.sourcePath) }
    }

    func save(_ records: [PersistedConversionItem], kind: ConversionMediaKind) {
        do {
            try fileManager.createDirectory(at: manifestsURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: manifestURL(kind), options: .atomic)
        } catch {
            // Persistence failure must not interrupt an active conversion.
        }
    }

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

    private func manifestURL(_ kind: ConversionMediaKind) -> URL {
        manifestsURL.appendingPathComponent("\(kind.rawValue).json")
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}
