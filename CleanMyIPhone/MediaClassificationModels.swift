//
//  MediaClassificationModels.swift
//  CleanMyIPhone
//

import Foundation

nonisolated struct DeviceStorageSnapshot: Codable, Equatable, Sendable {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

enum MediaAnalysisPhase: Equatable, Sendable {
    case discovering
    case generatingFeatures
    case comparingImages
}

struct MediaAnalysisProgress: Equatable, Sendable {
    let phase: MediaAnalysisPhase
    let completed: Int
    let total: Int

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum MediaAnalysisState: Equatable, Sendable {
    case idle
    case analyzing(MediaAnalysisProgress)
    case success(MediaClassificationResult)
    case empty
    case cancelled
    case partialFailure(MediaClassificationResult)
    case failure(MediaAnalysisError)

    var isAnalyzing: Bool {
        if case .analyzing = self { return true }
        return false
    }
}

enum MediaAnalysisError: LocalizedError, Equatable, Sendable {
    case photoAccessUnavailable
    case unexpected

    var errorDescription: String? {
        switch self {
        case .photoAccessUnavailable:
            String(localized: "Photo access is unavailable for analysis.")
        case .unexpected:
            String(localized: "Media analysis could not be completed.")
        }
    }
}

enum MediaDeletionState: Equatable, Sendable {
    case idle
    case deleting(itemCount: Int)
    case success(deletedCount: Int)
    case failure(MediaDeletionError)

    var isDeleting: Bool {
        if case .deleting = self { return true }
        return false
    }
}

enum MediaDeletionError: LocalizedError, Equatable, Sendable {
    case photoAccessUnavailable
    case noItemsSelected
    case deletionFailed

    var errorDescription: String? {
        switch self {
        case .photoAccessUnavailable:
            String(localized: "Photo access is unavailable for deletion.")
        case .noItemsSelected:
            String(localized: "Select at least one item to delete.")
        case .deletionFailed:
            String(localized: "The selected media could not be deleted.")
        }
    }
}

nonisolated enum VideoCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case longDuration
    case fourK
    case screenRecording
    case slowMotion
    case timeLapse

    var displayName: String {
        switch self {
        case .longDuration: String(localized: "Long Videos")
        case .fourK: String(localized: "4K Videos")
        case .screenRecording: String(localized: "Screen Recordings")
        case .slowMotion: String(localized: "Slow-motion Videos")
        case .timeLapse: String(localized: "Time-lapse Videos")
        }
    }
}

nonisolated struct ClassifiedVideo: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let categories: Set<VideoCategory>
}

nonisolated struct SimilarImageItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
}

nonisolated struct SimilarImageGroup: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let items: [SimilarImageItem]
    let suggestedKeeperID: String
}

nonisolated struct MediaClassificationResult: Codable, Equatable, Sendable {
    let similarImageGroups: [SimilarImageGroup]
    let classifiedVideos: [ClassifiedVideo]
    let screenshotIDs: [String]
    let livePhotoIDs: [String]
    let skippedImageCount: Int

    var videoIDs: [String] { classifiedVideos.map(\.id) }

    var similarImageIDs: [String] {
        similarImageGroups.flatMap { $0.items.map(\.id) }
    }

    var similarImageCount: Int {
        similarImageGroups.reduce(0) { $0 + $1.items.count }
    }

    func videoCount(in category: VideoCategory) -> Int {
        classifiedVideos.count { $0.categories.contains(category) }
    }

    func removingAssetIDs(_ removedIDs: Set<String>) -> MediaClassificationResult {
        let groups = similarImageGroups.compactMap { group -> SimilarImageGroup? in
            let remaining = group.items.filter { !removedIDs.contains($0.id) }
            guard remaining.count >= 2 else { return nil }
            return SimilarImageGroup(
                id: group.id,
                items: remaining,
                suggestedKeeperID: remaining.contains(where: { $0.id == group.suggestedKeeperID })
                    ? group.suggestedKeeperID
                    : remaining[0].id
            )
        }

        return MediaClassificationResult(
            similarImageGroups: groups,
            classifiedVideos: classifiedVideos.filter { !removedIDs.contains($0.id) },
            screenshotIDs: screenshotIDs.filter { !removedIDs.contains($0) },
            livePhotoIDs: livePhotoIDs.filter { !removedIDs.contains($0) },
            skippedImageCount: skippedImageCount
        )
    }
}
