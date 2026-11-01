//
//  媒体与存储模型行为
//
//  覆盖批量选择手势、分析进度、相似图片索引、日期和分类。
//  包括重叠分类去重、保护保留项及删除后结果更新。
//  检查手势方向、进度节流、哈希候选限制、存储排序和视频阈值。
//  分类与删除结果使用合成标识，保护项不会因候选集合重叠而丢失。
//

import Foundation
import Photos
import Testing
@testable import CleanMyIPhone

/// 验证媒体选择、分析、分类及结果派生规则。
@Suite("Media model behavior")
struct MediaModelTests {
    // Required: selection may only claim an explicitly horizontal gesture start.
    /// 纵向或对角线起始手势不得抢占列表滚动；参数覆盖多个方向与幅度。
    @Test("Vertical and diagonal starts stay available for scrolling", arguments: [
        CGPoint(x: 0, y: 30), CGPoint(x: 0, y: -30),
        CGPoint(x: 10, y: 30), CGPoint(x: -10, y: -30),
        CGPoint(x: 20, y: 20), CGPoint(x: 1, y: 1)
    ])
    func scrollingDoesNotBeginSelection(translation: CGPoint) {
        #expect(MediaBatchSelectionDirection.resolveStart(translation: translation, velocity: translation) == nil)
    }

    /// 水平位移和速度方向一致时才进入批量选择，避免误判垂直滚动。
    @Test("Horizontal starts retain batch selection in both directions")
    func horizontalStartsRemainSelectable() {
        #expect(MediaBatchSelectionDirection.resolveStart(translation: CGPoint(x: 10, y: 1), velocity: CGPoint(x: 100, y: 5)) == .right)
        #expect(MediaBatchSelectionDirection.resolveStart(translation: CGPoint(x: -10, y: 1), velocity: CGPoint(x: -100, y: 5)) == .left)
        #expect(MediaBatchSelectionDirection.resolveStart(translation: CGPoint(x: 10, y: 1), velocity: CGPoint(x: 5, y: 100)) == nil)
        #expect(MediaBatchSelectionDirection.resolveStart(translation: CGPoint(x: 10, y: 1), velocity: CGPoint(x: -100, y: 5)) == nil)
    }

    /// 连续手势向右或向下时解析为选择方向。
    @Test("Continuous batch selection maps right and down to selection")
    func batchSelectionPositiveDirectionsSelect() {
        #expect(
            MediaBatchSelectionDirection.resolve(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 30, y: 12)
            ) == .right
        )
        #expect(
            MediaBatchSelectionDirection.resolve(
                from: CGPoint(x: 30, y: 12),
                to: CGPoint(x: 32, y: 42)
            ) == .down
        )
        #expect(MediaBatchSelectionDirection.right.shouldSelect)
        #expect(MediaBatchSelectionDirection.down.shouldSelect)
    }

    /// 连续手势向左或向上时解析为取消选择方向。
    @Test("Continuous batch selection maps left and up to cancellation")
    func batchSelectionNegativeDirectionsCancel() {
        #expect(
            MediaBatchSelectionDirection.resolve(
                from: CGPoint(x: 30, y: 40),
                to: CGPoint(x: 8, y: 38)
            ) == .left
        )
        #expect(
            MediaBatchSelectionDirection.resolve(
                from: CGPoint(x: 8, y: 38),
                to: CGPoint(x: 7, y: 9)
            ) == .up
        )
        #expect(!MediaBatchSelectionDirection.left.shouldSelect)
        #expect(!MediaBatchSelectionDirection.up.shouldSelect)
    }

    /// 微小位移不足以确定方向，不应改变选择状态。
    @Test("Continuous batch selection ignores finger jitter")
    func batchSelectionIgnoresJitter() {
        #expect(
            MediaBatchSelectionDirection.resolve(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 11, y: 11)
            ) == nil
        )
    }

    /// 大量分析任务只报告约一百次进度，并保证最后一次对应完成。
    @Test("Analysis progress limits large workloads to about one hundred updates")
    func analysisProgressIsThrottled() {
        let reported = (1 ... 10_000).filter {
            MediaClassificationService.shouldReportProgress(completed: $0, total: 10_000)
        }

        #expect(reported.count == 100)
        #expect(reported.last == 10_000)
    }

    /// 小任务和空任务均能报告终点，防止界面停留在未完成状态。
    @Test("Analysis progress always reports completion for small workloads")
    func analysisProgressReportsFinalItem() {
        #expect(MediaClassificationService.shouldReportProgress(completed: 3, total: 3))
        #expect(MediaClassificationService.shouldReportProgress(completed: 0, total: 0))
    }

    /// 将内部比较工作量映射到用户可理解的图片数量，覆盖起点、中点与终点。
    @Test("Internal comparison work maps back to the real image count")
    func comparisonProgressUsesImageCount() {
        #expect(MediaClassificationService.displayProgress(
            completedWork: 0,
            totalWork: 4_000,
            imageCount: 2_000
        ) == 0)
        #expect(MediaClassificationService.displayProgress(
            completedWork: 2_000,
            totalWork: 4_000,
            imageCount: 2_000
        ) == 1_000)
        #expect(MediaClassificationService.displayProgress(
            completedWork: 4_000,
            totalWork: 4_000,
            imageCount: 2_000
        ) == 2_000)
    }

    /// 构造已知近似哈希，确认分段筛选仍能召回强相似候选。
    @Test("Segmented hash index keeps strong near matches")
    func segmentedHashIndexFindsStrongNearMatches() {
        let base: UInt64 = 0x0123_4567_89AB_CDEF
        let eightBitDifference = base ^ 0x0000_0000_0000_00FF
        let index = SegmentedHammingIndex(features: [
            CandidateFeature(id: "base", perceptualHash: base),
            CandidateFeature(id: "query", perceptualHash: eightBitDifference)
        ])
        let pairs = index.allPairs(
            maximumDistance: 16,
            maximumResults: 32,
            maximumEvaluationsPerImage: .max,
            workerCount: 1
        )

        #expect(pairs.count == 1)
        #expect(pairs.first?.firstIndex == 0)
        #expect(pairs.first?.secondIndex == 1)
    }

    /// 确认候选搜索遵守汉明距离和每项结果数量限制。
    @Test("Segmented hash index applies distance and result limits")
    func segmentedHashIndexHonorsLimits() {
        let index = SegmentedHammingIndex(features: [
            CandidateFeature(id: "a", perceptualHash: 0),
            CandidateFeature(id: "b", perceptualHash: 0),
            CandidateFeature(id: "c", perceptualHash: 0),
            CandidateFeature(id: "far", perceptualHash: .max)
        ])
        let pairs = index.allPairs(
            maximumDistance: 16,
            maximumResults: 1,
            maximumEvaluationsPerImage: .max,
            workerCount: 1
        )

        #expect(pairs.map(\.firstIndex) == [0, 0])
        #expect(pairs.map(\.secondIndex) == [1, 2])
    }

    /// 日期分组及同日资源都按时间倒序，使用固定时区避免环境差异。
    @Test("Media date sections and items sort newest first")
    func mediaDateSectionsSortNewestFirst() throws {
        let calendar = utcCalendar
        let olderMorning = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 25, hour: 9
        )))
        let olderEvening = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 25, hour: 18
        )))
        let newer = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 26, hour: 8
        )))

        let sections = MediaDateSectionBuilder.sections(from: [
            MediaDatedAsset(id: "older-morning", creationDate: olderMorning),
            MediaDatedAsset(id: "newer", creationDate: newer),
            MediaDatedAsset(id: "older-evening", creationDate: olderEvening)
        ], calendar: calendar)

        #expect(sections.count == 2)
        #expect(sections[0].assetIDs == ["newer"])
        #expect(sections[1].assetIDs == ["older-evening", "older-morning"])
    }

    /// 缺少创建日期的资源进入最后一组，并按标识保持确定顺序。
    @Test("Media without a creation date appears in the final section")
    func unknownMediaDatesAppearLast() throws {
        let knownDate = try #require(utcCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 26
        )))

        let sections = MediaDateSectionBuilder.sections(from: [
            MediaDatedAsset(id: "unknown-b", creationDate: nil),
            MediaDatedAsset(id: "known", creationDate: knownDate),
            MediaDatedAsset(id: "unknown-a", creationDate: nil)
        ], calendar: utcCalendar)

        #expect(sections.last?.day == nil)
        #expect(sections.last?.assetIDs == ["unknown-a", "unknown-b"])
    }

    /// 分组后每个资源标识仍恰好出现一次，包括缺少日期的资源。
    @Test("Date grouping preserves every media identifier exactly once")
    func mediaDateGroupingPreservesIdentifiers() throws {
        let date = try #require(utcCalendar.date(from: DateComponents(
            year: 2026, month: 8, day: 26
        )))
        let assets = [
            MediaDatedAsset(id: "one", creationDate: date),
            MediaDatedAsset(id: "two", creationDate: date),
            MediaDatedAsset(id: "three", creationDate: nil)
        ]

        let identifiers = MediaDateSectionBuilder.sections(from: assets, calendar: utcCalendar)
            .flatMap(\.assetIDs)

        #expect(identifiers.count == assets.count)
        #expect(Set(identifiers) == Set(assets.map { $0.id }))
    }

    /// 已知大小按降序排列，未知大小即使数值较大也排在后面。
    @Test("Storage files sort by known size descending and keep unknown sizes last")
    func storageFilesSortBySizeDescending() {
        let files = [
            scannedFile(name: "unknown", bytes: 9_999, hasKnownSize: false),
            scannedFile(name: "small", bytes: 10),
            scannedFile(name: "large", bytes: 1_000),
            scannedFile(name: "medium", bytes: 100)
        ]

        #expect(FileDisplayOrder.bySizeDescending(files).map { $0.name } == [
            "large", "medium", "small", "unknown"
        ])
    }

    /// 大小相同时按名称稳定排序，避免列表顺序随输入变化。
    @Test("Equal-size storage files have a stable name order")
    func equalSizeStorageFilesSortByName() {
        let files = [
            scannedFile(name: "Beta", bytes: 100),
            scannedFile(name: "Alpha", bytes: 100)
        ]

        #expect(FileDisplayOrder.bySizeDescending(files).map { $0.name } == ["Alpha", "Beta"])
    }

    /// 可用空间异常大于总容量时，已用空间和比例归零。
    @Test("Storage usage clamps negative used bytes to zero")
    func storageUsageClampsNegativeValues() {
        let snapshot = DeviceStorageSnapshot(totalBytes: 100, availableBytes: 140)

        #expect(snapshot.usedBytes == 0)
        #expect(snapshot.usedFraction == 0)
    }

    /// 无法取得容量时返回零比例，避免除以零。
    @Test("Storage usage is zero when capacity is unavailable")
    func storageUsageHandlesZeroCapacity() {
        let snapshot = DeviceStorageSnapshot(totalBytes: 0, availableBytes: 0)

        #expect(snapshot.usedFraction == 0)
    }

    /// 可用空间出现负数时，已用比例上限仍为一。
    @Test("Storage usage never exceeds one")
    func storageUsageIsClampedToOne() {
        let snapshot = DeviceStorageSnapshot(totalBytes: 100, availableBytes: -25)

        #expect(snapshot.usedFraction == 1)
    }

    /// 空工作量的进度为零，避免产生无效比例。
    @Test("Analysis progress handles an empty workload")
    func analysisProgressHandlesEmptyWorkload() {
        let progress = MediaAnalysisProgress(phase: .discovering, completed: 0, total: 0)

        #expect(progress.fractionCompleted == 0)
    }

    /// 验证已完成数量与总量的比例计算。
    @Test("Analysis progress reports its exact fraction")
    func analysisProgressReportsFraction() {
        let progress = MediaAnalysisProgress(phase: .generatingFeatures, completed: 3, total: 8)

        #expect(progress.fractionCompleted == 0.375)
    }

    /// 仅分析中状态报告活动，空闲、取消和空结果均停止活动指示。
    @Test("Only analyzing state is marked as active")
    func analysisStateActivityFlag() {
        let progress = MediaAnalysisProgress(phase: .discovering, completed: 0, total: 1)

        #expect(MediaAnalysisState.analyzing(progress).isAnalyzing)
        #expect(!MediaAnalysisState.idle.isAnalyzing)
        #expect(!MediaAnalysisState.cancelled.isAnalyzing)
        #expect(!MediaAnalysisState.empty.isAnalyzing)
    }

    /// 删除成功或失败后不再报告删除中。
    @Test("Only deleting state is marked as active")
    func deletionStateActivityFlag() {
        #expect(MediaDeletionState.deleting(itemCount: 2).isDeleting)
        #expect(!MediaDeletionState.idle.isDeleting)
        #expect(!MediaDeletionState.success(deletedCount: 2, estimatedBytes: 1_024).isDeleting)
        #expect(!MediaDeletionState.failure(.deletionFailed).isDeleting)
    }

    /// 比较 600 秒与略低于 600 秒，确保长视频阈值包含边界。
    @Test("Long video threshold is inclusive")
    func longVideoThresholdIsInclusive() {
        let below = MediaClassificationService.categories(
            duration: 599.99,
            pixelWidth: 1_920,
            pixelHeight: 1_080,
            mediaSubtypes: []
        )
        let boundary = MediaClassificationService.categories(
            duration: 600,
            pixelWidth: 1_920,
            pixelHeight: 1_080,
            mediaSubtypes: []
        )

        #expect(!below.contains(.longDuration))
        #expect(boundary.contains(.longDuration))
    }

    /// 相同 4K 尺寸横竖互换时均属于 4K 分类。
    @Test("4K classification accepts landscape and portrait dimensions")
    func fourKClassificationIsOrientationIndependent() {
        let landscape = MediaClassificationService.categories(
            duration: 1,
            pixelWidth: 3_840,
            pixelHeight: 2_160,
            mediaSubtypes: []
        )
        let portrait = MediaClassificationService.categories(
            duration: 1,
            pixelWidth: 2_160,
            pixelHeight: 3_840,
            mediaSubtypes: []
        )

        #expect(landscape == [.fourK])
        #expect(portrait == [.fourK])
    }

    /// 宽度比 4K 边界少一个像素时不能误归类。
    @Test("Resolution just below 4K is not classified as 4K")
    func resolutionBelowFourKIsExcluded() {
        let categories = MediaClassificationService.categories(
            duration: 1,
            pixelWidth: 3_839,
            pixelHeight: 2_160,
            mediaSubtypes: []
        )

        #expect(categories.isEmpty)
    }

    /// 分别验证录屏、慢动作和延时摄影的系统子类型映射。
    @Test("Every native video subtype maps independently")
    func nativeVideoSubtypeMapping() {
        let screen = MediaClassificationService.categories(
            duration: 1, pixelWidth: 1, pixelHeight: 1, mediaSubtypes: .videoScreenRecording
        )
        let slow = MediaClassificationService.categories(
            duration: 1, pixelWidth: 1, pixelHeight: 1, mediaSubtypes: .videoHighFrameRate
        )
        let lapse = MediaClassificationService.categories(
            duration: 1, pixelWidth: 1, pixelHeight: 1, mediaSubtypes: .videoTimelapse
        )

        #expect(screen == [.screenRecording])
        #expect(slow == [.slowMotion])
        #expect(lapse == [.timeLapse])
    }

    /// 相似图片与视频集合能暴露扁平标识列表和对应数量。
    @Test("Result exposes flattened media identifiers")
    func resultFlattensIdentifiers() {
        let result = makeResult()

        #expect(result.similarImageIDs == ["keeper", "similar", "third", "fourth"])
        #expect(result.similarImageCount == 4)
        #expect(result.videoIDs == ["video-1", "video-2"])
    }

    /// 同一视频可属于多个分类，每个分类独立计数。
    @Test("Video count includes assets belonging to multiple categories")
    func videoCountsOverlapByDesign() {
        let result = makeResult()

        #expect(result.videoCount(in: .fourK) == 2)
        #expect(result.videoCount(in: .longDuration) == 1)
        #expect(result.videoCount(in: .screenRecording) == 1)
        #expect(result.videoCount(in: .timeLapse) == 0)
    }

    /// 重叠分类只计一次，建议保留项即使属于其他分类也不会进入待清理集合。
    @Test("Cleanup review de-duplicates categories and protects keepers across categories")
    func cleanupReviewProtectsKeepersAndCountsOnce() {
        let result = MediaClassificationResult(
            similarImageGroups: [SimilarImageGroup(
                id: "group", items: [item("keeper"), item("extra")], suggestedKeeperID: "keeper"
            )],
            classifiedVideos: [],
            screenshotIDs: ["keeper", "extra", "screenshot"],
            livePhotoIDs: ["keeper", "extra", "live", "live"],
            skippedImageCount: 0
        )
        #expect(result.suggestedCleanupIDs == ["extra"])
        #expect(result.cleanupReviewIDs == ["extra", "screenshot", "live"])
        #expect(!result.cleanupReviewIDs.contains("keeper"))
        let updated = result.removingAssetIDs(["extra"])
        #expect(updated.suggestedCleanupIDs.isEmpty)
    }

    /// 相似组移除成员后只剩一项时不再作为相似组展示。
    @Test("Removing one similar image drops a group that becomes a singleton")
    func removingImageDropsSingletonGroup() {
        let updated = makeResult().removingAssetIDs(["similar"])

        #expect(updated.similarImageGroups.count == 1)
        #expect(updated.similarImageIDs == ["third", "fourth"])
    }

    /// 建议保留项被移除后，从剩余成员中选择新的保留项。
    @Test("Removing the suggested keeper selects the first remaining item")
    func removingKeeperChoosesReplacement() {
        let group = SimilarImageGroup(
            id: "group",
            items: [item("keeper"), item("next"), item("last")],
            suggestedKeeperID: "keeper"
        )
        let result = MediaClassificationResult(
            similarImageGroups: [group],
            classifiedVideos: [],
            screenshotIDs: [],
            livePhotoIDs: [],
            skippedImageCount: 0
        )

        let updated = result.removingAssetIDs(["keeper"])

        #expect(updated.similarImageGroups.first?.suggestedKeeperID == "next")
        #expect(updated.similarImageGroups.first?.items.map { $0.id } == ["next", "last"])
    }

    /// 删除标识同时更新视频、截图和实况集合，保留跳过数量。
    @Test("Removing assets updates every classification collection")
    func removingAssetsUpdatesEveryCollection() {
        let updated = makeResult().removingAssetIDs(["video-1", "shot-1", "live-1"])

        #expect(updated.videoIDs == ["video-2"])
        #expect(updated.screenshotIDs == ["shot-2"])
        #expect(updated.livePhotoIDs.isEmpty)
        #expect(updated.skippedImageCount == 3)
    }

    /// 不存在的标识不会改变已有分类结果。
    @Test("Removing unknown identifiers leaves the result unchanged")
    func removingUnknownIdentifiersIsNoOp() {
        let result = makeResult()

        #expect(result.removingAssetIDs(["missing"]) == result)
    }

    /// 构造包含重叠视频分类及多个相似组的固定结果，供删除与统计用例复用。
    private func makeResult() -> MediaClassificationResult {
        MediaClassificationResult(
            similarImageGroups: [
                SimilarImageGroup(
                    id: "group-1",
                    items: [item("keeper"), item("similar")],
                    suggestedKeeperID: "keeper"
                ),
                SimilarImageGroup(
                    id: "group-2",
                    items: [item("third"), item("fourth")],
                    suggestedKeeperID: "third"
                )
            ],
            classifiedVideos: [
                ClassifiedVideo(
                    id: "video-1",
                    duration: 700,
                    pixelWidth: 3_840,
                    pixelHeight: 2_160,
                    categories: [.longDuration, .fourK]
                ),
                ClassifiedVideo(
                    id: "video-2",
                    duration: 10,
                    pixelWidth: 3_840,
                    pixelHeight: 2_160,
                    categories: [.fourK, .screenRecording]
                )
            ],
            screenshotIDs: ["shot-1", "shot-2"],
            livePhotoIDs: ["live-1"],
            skippedImageCount: 3
        )
    }

    /// 以固定尺寸创建相似图片条目，只让标识随用例变化。
    private func item(_ id: String) -> SimilarImageItem {
        SimilarImageItem(id: id, pixelWidth: 100, pixelHeight: 100, creationDate: nil)
    }
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

/// 构造指定名称及大小状态的文件，用于验证展示排序。
private func scannedFile(
    name: String,
    bytes: Int64,
    hasKnownSize: Bool = true
) -> ScannedFile {
    ScannedFile(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        relativePathComponents: [name],
        category: .other,
        byteCount: bytes,
        hasKnownByteCount: hasKnownSize
    )
}
