import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportedPhotoFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            ImportedPhotoFile(url: try PhotoLibraryImport.copy(received.file))
        }
    }
}

struct ImportedVideoFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            ImportedVideoFile(url: try PhotoLibraryImport.copy(received.file))
        }
    }
}

enum PhotoLibraryImport {
    static func loadTransferable<T: Transferable & Sendable>(
        from item: PhotosPickerItem,
        type: T.Type,
        progress progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> T? {
        try await ConversionImportScheduler.shared.withPermit {
            try await loadTransferableWithoutScheduling(
                from: item,
                type: type,
                progress: progressHandler
            )
        }
    }

    private static func loadTransferableWithoutScheduling<T: Transferable & Sendable>(
        from item: PhotosPickerItem,
        type: T.Type,
        progress progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> T? {
        let operation = TransferProgressOperation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let transferProgress = item.loadTransferable(type: type) { result in
                    operation.finish()
                    progressHandler(1)
                    continuation.resume(with: result)
                }
                operation.attach(transferProgress)

                Task.detached {
                    var lastPercentage = -1
                    while true {
                        let snapshot = operation.snapshot()
                        let percentage = Int((snapshot.fraction * 100).rounded(.down))
                        if percentage != lastPercentage {
                            lastPercentage = percentage
                            progressHandler(snapshot.fraction)
                        }
                        if snapshot.isFinished { break }
                        // Ten UI updates per second remain smooth while avoiding
                        // excessive observation invalidations during large batches.
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }

    static func copy(_ sourceURL: URL) throws -> URL {
        let destination = try destinationURL(fileName: sourceURL.lastPathComponent)
        let fileManager = FileManager.default
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func destinationURL(fileName: String) throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent(
            "Media Conversion Imports",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = URL(fileURLWithPath: fileName)
        let originalName = source.deletingPathExtension().lastPathComponent
        let safeName = originalName.isEmpty ? "imported-media" : originalName
        return directory
            .appendingPathComponent("\(safeName)-\(UUID().uuidString)")
            .appendingPathExtension(source.pathExtension)
    }
}

private final class TransferProgressOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: Progress?
    private var finished = false

    func attach(_ progress: Progress) {
        lock.withLock {
            self.progress = progress
        }
    }

    func finish() {
        lock.withLock {
            finished = true
        }
    }

    func cancel() {
        lock.withLock {
            progress?.cancel()
            finished = true
        }
    }

    func snapshot() -> (fraction: Double, isFinished: Bool) {
        lock.withLock {
            (progress?.fractionCompleted ?? 0, finished)
        }
    }
}
