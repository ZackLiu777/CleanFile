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
        let identifiers = candidates.map(\.photoAssetIdentifier)
        let originals = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard originals.count == identifiers.count else {
            throw ConversionOriginalReplacementError.missingOriginal
        }

        try await PHPhotoLibrary.shared().performChanges {
            for candidate in candidates {
                switch candidate.kind {
                case .image:
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: candidate.outputURL)
                case .video:
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: candidate.outputURL)
                case .audio:
                    // Rejected by the validation above; retained for exhaustive switching.
                    break
                }
            }
            PHAssetChangeRequest.deleteAssets(originals)
        }
        return Set(candidates.map(\.id))
    }
}
