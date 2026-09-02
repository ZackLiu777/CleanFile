//
//  文件职责：集中定义 PhotoLibraryImport 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 定义 `ImportedPhotoFile` 的值语义数据与相关行为。
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

/// 定义 `ImportedVideoFile` 的值语义数据与相关行为。
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

/// 定义 `PhotoLibraryImport` 使用的有限状态或选项集合。
enum PhotoLibraryImport {
    /// 加载 `loadTransferable` 所需的数据，并将结果转换为当前层可消费的状态。
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

    /// 加载 `loadTransferableWithoutScheduling` 所需的数据，并将结果转换为当前层可消费的状态。
    private static func loadTransferableWithoutScheduling<T: Transferable & Sendable>(
        from item: PhotosPickerItem,
        type: T.Type,
        progress progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> T? {
        let performanceID = ConversionPerformance.begin("Conversion PhotoKit Transfer")
        defer { ConversionPerformance.end("Conversion PhotoKit Transfer", id: performanceID) }
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

    /// 封装 `copy` 对应的局部行为，供当前类型在统一入口下复用。
    static func copy(_ sourceURL: URL) throws -> URL {
        let performanceID = ConversionPerformance.begin("Conversion Provider Copy")
        defer { ConversionPerformance.end("Conversion Provider Copy", id: performanceID) }
        let destination = try destinationURL(fileName: sourceURL.lastPathComponent)
        let fileManager = FileManager.default
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    /// 封装 `destinationURL` 对应的局部行为，供当前类型在统一入口下复用。
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

/// 封装 `TransferProgressOperation` 的引用语义、状态与业务行为。
private final class TransferProgressOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: Progress?
    private var finished = false

    /// 封装 `attach` 对应的局部行为，供当前类型在统一入口下复用。
    func attach(_ progress: Progress) {
        lock.withLock {
            self.progress = progress
        }
    }

    /// 封装 `finish` 对应的局部行为，供当前类型在统一入口下复用。
    func finish() {
        lock.withLock {
            finished = true
        }
    }

    /// 取消 `cancel` 对应的进行中任务，并收敛到可继续操作的状态。
    func cancel() {
        lock.withLock {
            progress?.cancel()
            finished = true
        }
    }

    /// 封装 `snapshot` 对应的局部行为，供当前类型在统一入口下复用。
    func snapshot() -> (fraction: Double, isFinished: Bool) {
        lock.withLock {
            (progress?.fractionCompleted ?? 0, finished)
        }
    }
}
