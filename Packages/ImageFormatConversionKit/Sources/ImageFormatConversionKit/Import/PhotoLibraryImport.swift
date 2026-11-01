//
//  将 PhotosPicker 提供的图片和视频转换为应用可继续访问的本地文件。
//  导入受全局调度器约束，传输进度和取消通过受锁保护的状态桥接。
//  交付文件先落到临时路径并检查大小；发送方拥有的原文件只复制不移动。
//  图片和视频各自提供 Transferable 包装，转换页面通过统一入口发起传输。
//  传输完成后返回可由应用继续访问的路径，工作区后续负责自身的暂存与清理。
//

import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 图片传输交付后保存到应用可访问的本地路径。
struct ImportedPhotoFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            ImportedPhotoFile(url: try PhotoLibraryImport.adopt(received))
        }
    }
}

/// 视频传输交付后保存到应用可访问的本地路径。
struct ImportedVideoFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            ImportedVideoFile(url: try PhotoLibraryImport.adopt(received))
        }
    }
}

/// 桥接 PhotosPicker 的传输、进度、取消和交付文件保存。
enum PhotoLibraryImport {
    /// 通过共享调度器限制并发传输，然后加载指定的可传输类型。
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

    /// 将回调式传输转换为异步结果，并定期上报变化的百分比。
    /// 调用任务取消时向传输进度对象发送取消请求。
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

    /// 将交付文件保存为本地副本：发送方原件始终复制，临时交付文件可同卷移动。
    /// 先写入部分文件并检查大小，成功后再改名提交；失败时清理部分文件。
    static func adopt(_ received: ReceivedTransferredFile) throws -> URL {
        let performanceID = ConversionPerformance.begin("Conversion Provider Copy")
        defer { ConversionPerformance.end("Conversion Provider Copy", id: performanceID) }
        let sourceURL = received.file.standardizedFileURL
        let destination = try destinationURL(fileName: sourceURL.lastPathComponent)
        let partial = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".partial-\(UUID().uuidString)")
            .appendingPathExtension(destination.pathExtension)
        let fileManager = FileManager.default

        do {
            let sourceBytes = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if !received.isOriginalFile,
               isSameVolume(sourceURL, destination.deletingLastPathComponent()) {
                do {
                    try fileManager.moveItem(at: sourceURL, to: partial)
                } catch {
                    try? fileManager.removeItem(at: partial)
                    try fileManager.copyItem(at: sourceURL, to: partial)
                }
            } else {
                try fileManager.copyItem(at: sourceURL, to: partial)
            }

            guard let persistedBytes = try partial
                .resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let sourceBytes, sourceBytes != persistedBytes {
                throw CocoaError(.fileReadCorruptFile)
            }

            try fileManager.moveItem(at: partial, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
    }

    /// 无法读取卷标识时保守返回 false，调用方因此使用复制路径。
    private static func isSameVolume(_ source: URL, _ destinationDirectory: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let sourceVolume = try? source.resourceValues(forKeys: keys).volumeIdentifier,
              let destinationVolume = try? destinationDirectory
              .resourceValues(forKeys: keys).volumeIdentifier else {
            return false
        }
        return sourceVolume.isEqual(destinationVolume)
    }

    /// 在应用支持目录创建带 UUID 的导入路径，避免不同交付文件重名。
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

/// 用锁保护传输进度和完成状态，供回调、轮询和取消处理器共享。
private final class TransferProgressOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: Progress?
    private var finished = false

    /// 保存 PhotosPicker 返回的进度对象。
    func attach(_ progress: Progress) {
        lock.withLock {
            self.progress = progress
        }
    }

    /// 标记传输回调已结束，使进度轮询退出。
    func finish() {
        lock.withLock {
            finished = true
        }
    }

    /// 请求取消底层传输并停止进度轮询。
    func cancel() {
        lock.withLock {
            progress?.cancel()
            finished = true
        }
    }

    /// 原子读取进度和结束状态，避免观察到不一致的共享状态。
    func snapshot() -> (fraction: Double, isFinished: Bool) {
        lock.withLock {
            (progress?.fractionCompleted ?? 0, finished)
        }
    }
}
