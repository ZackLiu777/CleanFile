import Foundation
import Photos

struct ConversionReplacementCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let outputURL: URL
    let photoAssetIdentifier: String
    let kind: ConversionMediaKind
    let sourceBytes: Int64
    let outputBytes: Int64
}

enum ConversionOriginalReplacementError: Error {
    case missingOriginal
    case unsupportedOutput
    case missingOutput
    case creationFailed
}

/// Commits every compressed copy to Photos before deleting its matching original.
/// PhotoKit presents the system deletion confirmation and applies the batch as one change.
enum ConversionOriginalReplacementService {
    static let supportedKinds: Set<ConversionMediaKind> = [.image, .video]

    static func replace(_ candidates: [ConversionReplacementCandidate]) async throws -> Set<UUID> {
        guard !candidates.isEmpty else { return [] }
        guard candidates.allSatisfy({ supportedKinds.contains($0.kind) }) else {
            throw ConversionOriginalReplacementError.unsupportedOutput
        }
        guard candidates.allSatisfy({ candidate in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate.outputURL.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }) else {
            throw ConversionOriginalReplacementError.missingOutput
        }
        let identifiers = candidates.map(\.photoAssetIdentifier)
        let originals = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard originals.count == identifiers.count else {
            throw ConversionOriginalReplacementError.missingOriginal
        }

        var createdEveryCopy = true
        try await PHPhotoLibrary.shared().performChanges {
            for candidate in candidates {
                let request: PHAssetChangeRequest?
                switch candidate.kind {
                case .image:
                    request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: candidate.outputURL)
                case .video:
                    request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: candidate.outputURL)
                case .audio:
                    // Rejected by the validation above; retained for exhaustive switching.
                    request = nil
                }
                if request == nil {
                    createdEveryCopy = false
                    return
                }
            }
            PHAssetChangeRequest.deleteAssets(originals)
        }
        guard createdEveryCopy else { throw ConversionOriginalReplacementError.creationFailed }
        return Set(candidates.map(\.id))
    }
}
