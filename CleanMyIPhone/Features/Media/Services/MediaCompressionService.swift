import Foundation
import Photos
import ImageFormatConversionKit
import os

/// A batch owns one service and processes one asset at a time, bounding disk and decoder use.
actor MediaCompressionService {
    private let images = ImageConversionEngine()
    private let videos = VideoConversionEngine()
    private var replacements: [String: SavedCompressionReplacement] = [:]

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

    private func compressImage(_ source: URL, to output: URL) async throws -> URL {
        let info = try await images.inspect(source)
        guard info.frameCount == 1 else { throw MediaCompressionError.specialImage }
        let format: ImageOutputFormat = info.hasAlpha ? .png :
            ImageConversionEngine.supportedOutputFormats.contains(.heic) ? .heic : .jpeg
        return try await images.convert(ImageConversionRequest(sourceURL: source, destinationDirectory: output,
            outputFormat: format, quality: 0.5, metadataPolicy: .preserve,
            background: info.hasAlpha ? .transparent : nil)).outputURL
    }

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

    private func byteCount(_ urls: [URL]) throws -> Int64 {
        try urls.reduce(0) { $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    }

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
    private struct State {
        var handle: FileHandle?
        var requestID: PHAssetResourceDataRequestID?
        var cancelled = false
        var error: Error?
    }
    private let state: OSAllocatedUnfairLock<State>

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        state = OSAllocatedUnfairLock(initialState: State(handle: try FileHandle(forWritingTo: url)))
    }
    func install(_ id: PHAssetResourceDataRequestID) {
        let cancel = state.withLock { value in
            value.requestID = id
            return value.cancelled || value.error != nil
        }
        if cancel { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    func receive(_ data: Data) {
        let cancelID = state.withLock { value -> PHAssetResourceDataRequestID? in
            guard !value.cancelled, value.error == nil else { return nil }
            do { try value.handle?.write(contentsOf: data) }
            catch { value.error = error; return value.requestID }
            return nil
        }
        if let cancelID { PHAssetResourceManager.default().cancelDataRequest(cancelID) }
    }
    func cancel() {
        let id = state.withLock { value in value.cancelled = true; return value.requestID }
        if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
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
    deinit { state.withLock { try? $0.handle?.close() } }
}

nonisolated private struct SavedCompressionReplacement: Sendable {
    let copyID: String
    let modificationDate: Date?
    let category: MediaCompressionCategory
}
