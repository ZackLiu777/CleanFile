//
//  媒体压缩与原件替换
//
//  协调 PhotoKit 资源下载、原生转换、压缩副本保存和独立的原件替换。
//  副本必须更小并通过保存验证；替换前再次验证原件和副本，删除由 PhotoKit 事务执行。
//

import Foundation
import Photos
import ImageFormatConversionKit
import os

/// A batch owns one service and processes one asset at a time, bounding disk and decoder use.
/// 为单批次串行管理压缩操作及已保存副本，限制同时占用的临时磁盘和解码资源。
actor MediaCompressionService {
    private let images = ImageConversionEngine()
    private let videos = VideoConversionEngine()
    private var replacements: [String: SavedCompressionReplacement] = [:]

    /// 下载指定资源并生成压缩副本；只有输出更小时才保存，并验证新资源后记录可替换关系。
    /// 原件不会在此步骤删除；临时目录在操作结束后清理。
    func compress(id: String, category: MediaCompressionCategory) async throws -> MediaCompressionOutcome {
        try Task.checkCancellation()
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaCompression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("output", isDirectory: true)
        let resources = PHAssetResource.assetResources(for: asset)
        // If the edited rendition is missing, do not silently save a copy of the unedited original.
        if resources.contains(where: { $0.type == .adjustmentData }) {
            let required: [PHAssetResourceType] = switch category {
            case .video: [.fullSizeVideo]
            case .image: [.fullSizePhoto]
            case .live: [.fullSizePhoto, .fullSizePairedVideo]
            }
            guard required.allSatisfy({ type in resources.contains { $0.type == type } }) else {
                throw CocoaError(.fileReadUnknown)
            }
        }
        var sources: [URL] = []
        var outputs: [URL] = []
        if category == .video {
            guard let resource = resources.first(where: { $0.type == .fullSizeVideo }) ?? resources.first(where: { $0.type == .video }) else { throw CocoaError(.fileReadUnknown) }
            let source = try await download(resource, to: folder, name: "video")
            sources = [source]
            outputs = [try await compressVideo(source, to: output, live: false)]
        } else if category == .live {
            // Never mix an edited still with the original paired movie.
            let editedPhoto = resources.first { $0.type == .fullSizePhoto }
            let editedMovie = resources.first { $0.type == .fullSizePairedVideo }
            guard (editedPhoto == nil) == (editedMovie == nil) else { throw MediaCompressionError.invalidLivePhoto }
            let usesEditedPair = editedPhoto != nil && editedMovie != nil
            guard let photo = usesEditedPair ? editedPhoto : resources.first(where: { $0.type == .photo }),
                  let movie = usesEditedPair ? editedMovie : resources.first(where: { $0.type == .pairedVideo }) else { throw CocoaError(.fileReadUnknown) }
            let still = try await download(photo, to: folder, name: "photo")
            let motion = try await download(movie, to: folder, name: "motion")
            sources = [still, motion]
            let compressedMotion = try await compressVideo(motion, to: output, live: true)
            let compressedStill = try await compressImage(still, to: output)
            if await validLivePhoto([compressedStill, compressedMotion]) {
                outputs = [compressedStill, compressedMotion]
            } else {
                // Some source formats cannot carry their pairing metadata through ImageIO.
                // Preserve that still component instead of turning a Live Photo into a static image.
                guard await validLivePhoto([still, compressedMotion]) else { throw MediaCompressionError.invalidLivePhoto }
                outputs = [still, compressedMotion]
            }
        } else {
            guard !asset.mediaSubtypes.contains(.photoLive),
                  let photo = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) else { throw CocoaError(.fileReadUnknown) }
            let source = try await download(photo, to: folder, name: "photo")
            sources = [source]
            outputs = [try await compressImage(source, to: output)]
        }

        try Task.checkCancellation()
        let originalBytes = try byteCount(sources)
        let outputBytes = try byteCount(outputs)
        guard outputBytes < originalBytes else { return .noReduction(original: originalBytes) }
        // A committed copy is retained even if cancellation arrives. Originals are deleted only after the batch verifies every copy.
        let date = asset.creationDate
        let location = asset.location
        let savedURLs = outputs
        let identifier = OSAllocatedUnfairLock<String?>(initialState: nil)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = date
            request.location = location
            request.addResource(with: category == .video ? .video : .photo, fileURL: savedURLs[0], options: nil)
            if category == .live { request.addResource(with: .pairedVideo, fileURL: savedURLs[1], options: nil) }
            identifier.withLock { $0 = request.placeholderForCreatedAsset?.localIdentifier }
        }
        guard let copyID = identifier.withLock({ $0 }), copyID != id,
              let copy = PHAsset.fetchAssets(withLocalIdentifiers: [copyID], options: nil).firstObject,
              copy.mediaType == asset.mediaType,
              category != .live || copy.mediaSubtypes.contains(.photoLive) else {
            throw MediaCompressionError.verificationFailed
        }
        replacements[id] = SavedCompressionReplacement(copyID: copyID, modificationDate: asset.modificationDate,
                                                        category: category)
        return .saved(original: originalBytes, output: outputBytes, createdAssetID: copyID)
    }

    /// 确认所有原件仍存在且未在压缩后修改，并逐一核对已保存副本后，统一请求 PhotoKit 删除。
    /// 系统拒绝或验证失败会抛出错误；用户取消被转换为取消错误。
    func replaceOriginals(_ ids: Set<String>) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        try Task.checkCancellation()
        let originals = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        guard originals.count == ids.count else { throw MediaCompressionError.replacementFailed }
        let copyIDs = ids.compactMap { replacements[$0]?.copyID }
        guard copyIDs.count == ids.count, Set(copyIDs).count == ids.count else {
            throw MediaCompressionError.replacementFailed
        }
        let fetchedCopies = PHAsset.fetchAssets(withLocalIdentifiers: copyIDs, options: nil)
        guard fetchedCopies.count == copyIDs.count else { throw MediaCompressionError.replacementFailed }
        var copiesByID: [String: PHAsset] = [:]
        fetchedCopies.enumerateObjects { copy, _, _ in copiesByID[copy.localIdentifier] = copy }
        for index in 0..<originals.count {
            let original = originals.object(at: index)
            guard let replacement = replacements[original.localIdentifier],
                  original.modificationDate == replacement.modificationDate,
                  let copy = copiesByID[replacement.copyID],
                  copy.localIdentifier != original.localIdentifier,
                  copy.mediaType == original.mediaType,
                  replacement.category != .live || copy.mediaSubtypes.contains(.photoLive) else {
                throw MediaCompressionError.replacementFailed
            }
        }
        try Task.checkCancellation()
        do {
            // One PhotoKit transaction gives the system one deletion confirmation for the batch.
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(originals) }
        } catch {
            let photoError = error as NSError
            if photoError.domain == PHPhotosError.errorDomain,
               photoError.code == PHPhotosError.Code.userCancelled.rawValue { throw CancellationError() }
            throw MediaCompressionError.replacementFailed
        }
        ids.forEach { replacements[$0] = nil }
        return ids
    }

    /// 检查单帧约束后选择保留透明度的输出格式，并保留源元数据。
    private func compressImage(_ source: URL, to output: URL) async throws -> URL {
        let info = try await images.inspect(source)
        guard info.frameCount == 1 else { throw MediaCompressionError.specialImage }
        let format: ImageOutputFormat = info.hasAlpha ? .png :
            ImageConversionEngine.supportedOutputFormats.contains(.heic) ? .heic : .jpeg
        return try await images.convert(ImageConversionRequest(sourceURL: source, destinationDirectory: output,
            outputFormat: format, quality: 0.5, metadataPolicy: .preserve,
            background: info.hasAlpha ? .transparent : nil)).outputURL
    }

    /// 优先按目标码率转换；当系统不支持 HDR 指定码率时回退到保留 HDR 的导出路径。
    private func compressVideo(_ source: URL, to output: URL, live: Bool) async throws -> URL {
        do {
            let result = try await videos.convert(VideoConversionRequest(sourceURL: source, destinationDirectory: output,
                container: live ? .mov : .mp4, codec: .hevc, resolution: .original,
                bitRateFraction: 0.5, preservesTimedMetadata: live), progress: { _ in })
            return result.outputURL
        } catch VideoConversionError.hdrBitrateUnsupported {
            // The system exporter retains HDR. Never send HDR through the SDR bitrate encoder.
            let result = try await videos.convert(VideoConversionRequest(sourceURL: source, destinationDirectory: output,
                container: live ? .mov : .mp4, codec: .hevc, resolution: .original,
                preservesTimedMetadata: live), progress: { _ in })
            return result.outputURL
        }
    }

    /// 汇总临时资源的文件大小；元数据查询抛错时向上传递，缺少大小值时按零计入。
    private func byteCount(_ urls: [URL]) throws -> Int64 {
        try urls.reduce(0) { $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    }

    /// 将 PhotoKit 数据流写入临时文件，允许从云端获取资源并将任务取消转发给请求。
    private func download(_ resource: PHAssetResource, to folder: URL, name: String) async throws -> URL {
        let ext = (resource.originalFilename as NSString).pathExtension
        let url = folder.appendingPathComponent(name).appendingPathExtension(ext.isEmpty ? "dat" : ext)
        let transfer = try MediaResourceDownload(url: url)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options,
                    dataReceivedHandler: { transfer.receive($0) }, completionHandler: { error in
                        continuation.resume(with: transfer.finish(error: error))
                    })
                transfer.install(id)
            }
        } onCancel: { transfer.cancel() }
        try Task.checkCancellation()
        return url
    }

    /// 通过 PhotoKit 验证静态图与视频能否组成 Live Photo，忽略低质量中间回调。
    private func validLivePhoto(_ urls: [URL]) async -> Bool {
        await withCheckedContinuation { continuation in
            PHLivePhoto.request(withResourceFileURLs: urls, placeholderImage: nil,
                                targetSize: CGSize(width: 64, height: 64), contentMode: .aspectFit) { photo, info in
                guard (info[PHLivePhotoInfoIsDegradedKey] as? Bool) != true else { return }
                continuation.resume(returning: photo != nil && info[PHLivePhotoInfoErrorKey] == nil)
            }
        }
    }
}

/// 区分无法保留 Live Photo、特殊图片及副本验证或原件替换失败等可展示错误。
nonisolated enum MediaCompressionError: LocalizedError {
    case invalidLivePhoto, specialImage, verificationFailed, replacementFailed
    var errorDescription: String? {
        switch self {
        case .invalidLivePhoto: NSLocalizedString("compression.error.live", comment: "")
        case .specialImage: NSLocalizedString("compression.error.image", comment: "")
        case .verificationFailed: NSLocalizedString("compression.error.verify", comment: "")
        case .replacementFailed: NSLocalizedString("compression.error.replace", comment: "")
        }
    }
}

/// PhotoKit callbacks may arrive outside the actor. The mutex owns the stream and request lifecycle.
nonisolated private final class MediaResourceDownload: Sendable {
    /// 由锁保护的下载状态，协调 PhotoKit 回调、取消请求和文件写入错误。
    private struct State {
        var handle: FileHandle?
        var requestID: PHAssetResourceDataRequestID?
        var cancelled = false
        var error: Error?
    }
    private let state: OSAllocatedUnfairLock<State>

    /// 在指定临时 URL 创建空文件并打开写入句柄；创建或打开失败时抛出错误。
    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        state = OSAllocatedUnfairLock(initialState: State(handle: try FileHandle(forWritingTo: url)))
    }
    /// 记录异步请求标识；若安装前已经取消或写入失败，立即取消该请求。
    func install(_ id: PHAssetResourceDataRequestID) {
        let cancel = state.withLock { value in
            value.requestID = id
            return value.cancelled || value.error != nil
        }
        if cancel { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    /// 在锁保护下将回调数据增量写入文件；写入失败时取消正在进行的资源请求。
    func receive(_ data: Data) {
        let cancelID = state.withLock { value -> PHAssetResourceDataRequestID? in
            guard !value.cancelled, value.error == nil else { return nil }
            do { try value.handle?.write(contentsOf: data) }
            catch { value.error = error; return value.requestID }
            return nil
        }
        if let cancelID { PHAssetResourceManager.default().cancelDataRequest(cancelID) }
    }
    /// 记录取消状态并取消已安装的请求，兼容请求标识尚未返回的竞态。
    func cancel() {
        let id = state.withLock { value in value.cancelled = true; return value.requestID }
        if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    /// 关闭文件并统一返回取消、写入错误或 PhotoKit 错误，确保调用方只处理最终结果。
    func finish(error: Error?) -> Result<Void, Error> {
        state.withLock { value in
            do { try value.handle?.close() } catch { value.error = value.error ?? error }
            value.handle = nil
            value.requestID = nil
            if value.cancelled { return .failure(CancellationError()) }
            if let error = value.error ?? error { return .failure(error) }
            return .success(())
        }
    }
    /// 若请求未正常完成，释放时尽力关闭剩余句柄。
    deinit { state.withLock { try? $0.handle?.close() } }
}

/// 记录压缩副本与原件修改时间，供后续替换前核对资源是否发生变化。
nonisolated private struct SavedCompressionReplacement: Sendable {
    let copyID: String
    let modificationDate: Date?
    let category: MediaCompressionCategory
}
