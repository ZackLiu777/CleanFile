import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Used by a Shortcuts action that receives images or videos from the share sheet.
/// The foreground app owns navigation and compression; the intent only stages input.
struct ImportMediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Import to Filevra"
    static let description = IntentDescription("Open Filevra to compress shared images or videos.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Media", supportedContentTypes: [.image, .movie])
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$files) to Filevra")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !files.isEmpty else { throw ImportError.noSupportedFiles }
        let batchID = UUID()
        let directory = try ShareImportInbox.directory(for: batchID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var staged: [(Int, ShareImportInbox.Entry)] = []
        await withTaskGroup(of: (Int, ShareImportInbox.Entry?).self) { group in
            var nextIndex = 0
            for _ in 0..<min(3, files.count) {
                let index = nextIndex
                group.addTask { (index, await Self.stage(files[index], in: directory)) }
                nextIndex += 1
            }
            for await result in group {
                if let entry = result.1 { staged.append((result.0, entry)) }
                if nextIndex < files.count {
                    let index = nextIndex
                    group.addTask { (index, await Self.stage(files[index], in: directory)) }
                    nextIndex += 1
                }
            }
        }

        let entries = staged.sorted { $0.0 < $1.0 }.map(\.1)
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: directory)
            throw ImportError.noSupportedFiles
        }
        let batch = ShareImportInbox.Batch(id: batchID, createdAt: Date(), entries: entries)
        try JSONEncoder().encode(batch).write(
            to: directory.appendingPathComponent("manifest.json"), options: .atomic
        )
        NotificationCenter.default.post(name: .cleanFileShareImportReady, object: nil)
        return .result()
    }

    private static func stage(_ file: IntentFile, in directory: URL) async -> ShareImportInbox.Entry? {
        let filenameType = UTType(filenameExtension: (file.filename as NSString).pathExtension)
        let type = file.type ?? filenameType
        guard let type,
              let ext = (type.preferredFilenameExtension ?? filenameType?.preferredFilenameExtension)?.lowercased()
        else { return nil }
        let kind: ShareImportInbox.Kind
        if type.conforms(to: .movie), ["mov", "mp4", "m4v"].contains(ext) {
            kind = .video
        } else if type.conforms(to: .image),
                  ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"].contains(ext) {
            kind = .image
        } else {
            return nil
        }

        let entry = ShareImportInbox.Entry(id: UUID(), kind: kind,
                                           fileName: "\(UUID().uuidString).\(ext)")
        let destination = directory.appendingPathComponent(entry.fileName)
        do {
            try await file.withFile(contentType: type, allowOpenInPlace: true) { source, _ in
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            return entry
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }

    private enum ImportError: LocalizedError {
        case noSupportedFiles

        var errorDescription: String? {
            switch self {
            case .noSupportedFiles: "No supported images or videos could be imported."
            }
        }
    }
}

extension Notification.Name {
    static let cleanFileShareImportReady = Notification.Name("cleanFileShareImportReady")
}

struct CleanFileAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImportMediaIntent(),
            phrases: ["Import media with \(.applicationName)"],
            shortTitle: "Import Media",
            systemImageName: "square.and.arrow.down"
        )
    }
}
