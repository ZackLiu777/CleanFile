//
//  媒体分析与删除状态模型
//
//  集中定义相册分类、相似组、进度、错误及删除结果等值类型。
//  分类结果描述候选和状态，不直接代表用户授权删除资源。
//

//
//  MediaClassificationModels.swift
//  CleanMyIPhone
//

//
//  文件职责：定义 MediaClassification 领域使用的数据模型与状态语义。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 设备总容量和可用容量的快照；已用容量及占比限制在有效范围内。
nonisolated struct DeviceStorageSnapshot: Codable, Equatable, Sendable {
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

/// 媒体分析当前阶段，用于区分发现资源、生成特征和比较图片。
enum MediaAnalysisPhase: Equatable, Sendable {
    case discovering
    case generatingFeatures
    case comparingImages
}

/// 当前阶段的已完成量和总量；总量为零时展示进度为零。
struct MediaAnalysisProgress: Equatable, Sendable {
    let phase: MediaAnalysisPhase
    let completed: Int
    let total: Int

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

/// 媒体分析的互斥状态，区分成功、空结果、取消、部分失败和整体失败。
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

/// 媒体访问不可用或分析异常时向界面提供可本地化的错误。
enum MediaAnalysisError: LocalizedError, Equatable, Sendable {
    case photoAccessUnavailable
    case unexpected

    var errorDescription: String? {
        switch self {
        case .photoAccessUnavailable:
            AppL10n.string("Photo access is unavailable for analysis.")
        case .unexpected:
            AppL10n.string("Media analysis could not be completed.")
        }
    }
}

/// 相册删除操作的空闲、进行中、成功和失败状态。
enum MediaDeletionState: Equatable, Sendable {
    case idle
    case deleting(itemCount: Int)
    case success(deletedCount: Int, estimatedBytes: Int64)
    case failure(MediaDeletionError)

    var isDeleting: Bool {
        if case .deleting = self { return true }
        return false
    }
}

/// 区分授权失效、未选资源、资源已不可用及系统删除失败。
enum MediaDeletionError: LocalizedError, Equatable, Sendable {
    case photoAccessUnavailable
    case noItemsSelected
    case itemsUnavailable
    case deletionFailed

    var errorDescription: String? {
        switch self {
        case .photoAccessUnavailable:
            AppL10n.string("Photo access is unavailable for deletion.")
        case .noItemsSelected:
            AppL10n.string("Select at least one item to delete.")
        case .itemsUnavailable:
            AppL10n.string("Some selected media is no longer available. Refresh and try again.")
        case .deletionFailed:
            AppL10n.string("The selected media could not be deleted.")
        }
    }
}

/// 视频的可重叠分类，供分类结果和本地化标题使用。
nonisolated enum VideoCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case longDuration
    case fourK
    case screenRecording
    case slowMotion
    case timeLapse

    var displayName: String {
        switch self {
        case .longDuration: AppL10n.string("Long Videos")
        case .fourK: AppL10n.string("4K Videos")
        case .screenRecording: AppL10n.string("Screen Recordings")
        case .slowMotion: AppL10n.string("Slow-motion Videos")
        case .timeLapse: AppL10n.string("Time-lapse Videos")
        }
    }
}

/// 保存视频标识、时长、像素尺寸及所有适用分类。
nonisolated struct ClassifiedVideo: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let categories: Set<VideoCategory>
}

/// 相似组内资源的标识、尺寸和可选日期，用于排序与展示。
nonisolated struct SimilarImageItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
}

/// 一组相似资源及建议保留的资源标识；建议不等同于删除授权。
nonisolated struct SimilarImageGroup: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let items: [SimilarImageItem]
    let suggestedKeeperID: String
}

/// 媒体分类的完整结果及派生候选集合；跨分类资源通过集合去重并保护建议保留项。
nonisolated struct MediaClassificationResult: Codable, Equatable, Sendable {
    let similarImageGroups: [SimilarImageGroup]
    let classifiedVideos: [ClassifiedVideo]
    let screenshotIDs: [String]
    let livePhotoIDs: [String]
    let skippedImageCount: Int

    var videoIDs: [String] { classifiedVideos.map(\.id) }

    var protectedKeeperIDs: Set<String> { Set(similarImageGroups.map(\.suggestedKeeperID)) }

    var suggestedCleanupIDs: Set<String> {
        Set(similarImageGroups.flatMap { $0.items.map(\.id) }).subtracting(protectedKeeperIDs)
    }

    // Categories overlap. Count each candidate once, and never include a keeper.
    var cleanupReviewIDs: Set<String> {
        suggestedCleanupIDs.union(screenshotIDs).union(videoIDs).union(livePhotoIDs).subtracting(protectedKeeperIDs)
    }


    var similarImageIDs: [String] {
        similarImageGroups.flatMap { $0.items.map(\.id) }
    }

    var similarImageCount: Int {
        similarImageGroups.reduce(0) { $0 + $1.items.count }
    }

    /// 统计包含指定标签的视频；同一视频可以计入其他标签。
    func videoCount(in category: VideoCategory) -> Int {
        classifiedVideos.count { $0.categories.contains(category) }
    }

    /// 从结果中移除已删除标识，丢弃不足两项的相似组，并在保留项消失时重新指定首项。
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
