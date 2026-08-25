import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct ImportedPhotoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            ImportedPhotoFile(url: try PhotoLibraryImport.copy(received.file))
        }
    }
}

struct ImportedVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            ImportedVideoFile(url: try PhotoLibraryImport.copy(received.file))
        }
    }
}

private enum PhotoLibraryImport {
    static func copy(_ sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent(
            "Media Conversion Imports",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let safeName = originalName.isEmpty ? "imported-media" : originalName
        let destination = directory
            .appendingPathComponent("\(safeName)-\(UUID().uuidString)")
            .appendingPathExtension(sourceURL.pathExtension)
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
