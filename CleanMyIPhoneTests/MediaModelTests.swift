import Foundation
import Photos
import Testing
@testable import CleanMyIPhone

@Suite("Media model behavior")
struct MediaModelTests {
    @Test("Analysis progress limits large workloads to about one hundred updates")
    func analysisProgressIsThrottled() {
        let reported = (1 ... 10_000).filter {
            MediaClassificationService.shouldReportProgress(completed: $0, total: 10_000)
        }

        #expect(reported.count == 100)
        #expect(reported.last == 10_000)
    }

    @Test("Analysis progress always reports completion for small workloads")
    func analysisProgressReportsFinalItem() {
        #expect(MediaClassificationService.shouldReportProgress(completed: 3, total: 3))
        #expect(MediaClassificationService.shouldReportProgress(completed: 0, total: 0))
    }

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
        #expect(Set(identifiers) == Set(assets.map(\.id)))
    }

    @Test("Storage files sort by known size descending and keep unknown sizes last")
    func storageFilesSortBySizeDescending() {
        let files = [
            scannedFile(name: "unknown", bytes: 9_999, hasKnownSize: false),
            scannedFile(name: "small", bytes: 10),
            scannedFile(name: "large", bytes: 1_000),
            scannedFile(name: "medium", bytes: 100)
        ]

        #expect(FileDisplayOrder.bySizeDescending(files).map(\.name) == [
            "large", "medium", "small", "unknown"
        ])
    }

    @Test("Equal-size storage files have a stable name order")
    func equalSizeStorageFilesSortByName() {
        let files = [
            scannedFile(name: "Beta", bytes: 100),
            scannedFile(name: "Alpha", bytes: 100)
        ]

        #expect(FileDisplayOrder.bySizeDescending(files).map(\.name) == ["Alpha", "Beta"])
    }

    @Test("Storage usage clamps negative used bytes to zero")
    func storageUsageClampsNegativeValues() {
        let snapshot = DeviceStorageSnapshot(totalBytes: 100, availableBytes: 140)

        #expect(snapshot.usedBytes == 0)
        #expect(snapshot.usedFraction == 0)
    }

    @Test("Storage usage is zero when capacity is unavailable")
    func storageUsageHandlesZeroCapacity() {
        let snapshot = DeviceStorageSnapshot(totalBytes: 0, availableBytes: 0)

        #expect(snapshot.usedFraction == 0)
    }

    @Test("Storage usage never exceeds one")
    func storageUsageIsClampedToOne() {
        let snapshot = DeviceStorageSnapshot(totalBytes: 100, availableBytes: -25)

        #expect(snapshot.usedFraction == 1)
    }

    @Test("Analysis progress handles an empty workload")
    func analysisProgressHandlesEmptyWorkload() {
        let progress = MediaAnalysisProgress(phase: .discovering, completed: 0, total: 0)

        #expect(progress.fractionCompleted == 0)
    }

    @Test("Analysis progress reports its exact fraction")
    func analysisProgressReportsFraction() {
        let progress = MediaAnalysisProgress(phase: .generatingFeatures, completed: 3, total: 8)

        #expect(progress.fractionCompleted == 0.375)
    }

    @Test("Only analyzing state is marked as active")
    func analysisStateActivityFlag() {
        let progress = MediaAnalysisProgress(phase: .discovering, completed: 0, total: 1)

        #expect(MediaAnalysisState.analyzing(progress).isAnalyzing)
        #expect(!MediaAnalysisState.idle.isAnalyzing)
        #expect(!MediaAnalysisState.cancelled.isAnalyzing)
        #expect(!MediaAnalysisState.empty.isAnalyzing)
    }

    @Test("Only deleting state is marked as active")
    func deletionStateActivityFlag() {
        #expect(MediaDeletionState.deleting(itemCount: 2).isDeleting)
        #expect(!MediaDeletionState.idle.isDeleting)
        #expect(!MediaDeletionState.success(deletedCount: 2).isDeleting)
        #expect(!MediaDeletionState.failure(.deletionFailed).isDeleting)
    }

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

    @Test("Result exposes flattened media identifiers")
    func resultFlattensIdentifiers() {
        let result = makeResult()

        #expect(result.similarImageIDs == ["keeper", "similar", "third", "fourth"])
        #expect(result.similarImageCount == 4)
        #expect(result.videoIDs == ["video-1", "video-2"])
    }

    @Test("Video count includes assets belonging to multiple categories")
    func videoCountsOverlapByDesign() {
        let result = makeResult()

        #expect(result.videoCount(in: .fourK) == 2)
        #expect(result.videoCount(in: .longDuration) == 1)
        #expect(result.videoCount(in: .screenRecording) == 1)
        #expect(result.videoCount(in: .timeLapse) == 0)
    }

    @Test("Removing one similar image drops a group that becomes a singleton")
    func removingImageDropsSingletonGroup() {
        let updated = makeResult().removingAssetIDs(["similar"])

        #expect(updated.similarImageGroups.count == 1)
        #expect(updated.similarImageIDs == ["third", "fourth"])
    }

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
        #expect(updated.similarImageGroups.first?.items.map(\.id) == ["next", "last"])
    }

    @Test("Removing assets updates every classification collection")
    func removingAssetsUpdatesEveryCollection() {
        let updated = makeResult().removingAssetIDs(["video-1", "shot-1", "live-1"])

        #expect(updated.videoIDs == ["video-2"])
        #expect(updated.screenshotIDs == ["shot-2"])
        #expect(updated.livePhotoIDs.isEmpty)
        #expect(updated.skippedImageCount == 3)
    }

    @Test("Removing unknown identifiers leaves the result unchanged")
    func removingUnknownIdentifiersIsNoOp() {
        let result = makeResult()

        #expect(result.removingAssetIDs(["missing"]) == result)
    }

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

    private func item(_ id: String) -> SimilarImageItem {
        SimilarImageItem(id: id, pixelWidth: 100, pixelHeight: 100, creationDate: nil)
    }
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

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
