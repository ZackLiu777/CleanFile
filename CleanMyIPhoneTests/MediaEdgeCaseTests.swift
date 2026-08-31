import Foundation
import Photos
import Testing
@testable import CleanMyIPhone

@Suite("Media analysis edge cases")
struct MediaEdgeCaseTests {
    @Test("Empty date input produces no sections")
    func emptyDateInputIsEmpty() {
        #expect(MediaDateSectionBuilder.sections(from: []).isEmpty)
    }

    @Test("Assets on the same day are grouped regardless of time zone offset")
    func sameDayAssetsShareOneSection() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 0)))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 23)))

        let sections = MediaDateSectionBuilder.sections(
            from: [
                MediaDatedAsset(id: "late", creationDate: evening),
                MediaDatedAsset(id: "early", creationDate: morning)
            ],
            calendar: calendar
        )

        #expect(sections.count == 1)
        #expect(sections[0].assetIDs == ["late", "early"])
    }

    @Test("Unknown dates are isolated after known dates and sorted by identifier")
    func unknownDateOrderingIsStable() throws {
        let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 31)))
        let sections = MediaDateSectionBuilder.sections(from: [
            MediaDatedAsset(id: "z", creationDate: nil),
            MediaDatedAsset(id: "a", creationDate: nil),
            MediaDatedAsset(id: "known", creationDate: date)
        ])

        #expect(sections.count == 2)
        #expect(sections.last?.day == nil)
        #expect(sections.last?.assetIDs == ["a", "z"])
    }

    @Test("Video categorization handles negative and zero metadata without inventing labels")
    func invalidVideoMetadataProducesNoCategories() {
        let categories = MediaClassificationService.categories(
            duration: -1,
            pixelWidth: 0,
            pixelHeight: 0,
            mediaSubtypes: []
        )

        #expect(categories.isEmpty)
    }

    @Test("Video threshold boundaries remain inclusive for duration and dimensions")
    func videoBoundariesAreInclusive() {
        let categories = MediaClassificationService.categories(
            duration: 600,
            pixelWidth: 3_840,
            pixelHeight: 1,
            mediaSubtypes: []
        )

        #expect(categories == [.longDuration, .fourK])
    }

    @Test("All supported native video subtypes can coexist")
    func videoSubtypesCompose() {
        let categories = MediaClassificationService.categories(
            duration: 1,
            pixelWidth: 1,
            pixelHeight: 1,
            mediaSubtypes: [.videoScreenRecording, .videoHighFrameRate, .videoTimelapse]
        )

        #expect(categories == [.screenRecording, .slowMotion, .timeLapse])
    }

    @Test("Removing every item removes groups without leaving stale identifiers")
    func removingEveryResultItemProducesEmptyCollections() {
        let result = MediaClassificationResult(
            similarImageGroups: [
                SimilarImageGroup(
                    id: "group",
                    items: [
                        SimilarImageItem(id: "one", pixelWidth: 1, pixelHeight: 1, creationDate: nil),
                        SimilarImageItem(id: "two", pixelWidth: 1, pixelHeight: 1, creationDate: nil)
                    ],
                    suggestedKeeperID: "one"
                )
            ],
            classifiedVideos: [ClassifiedVideo(id: "video", duration: 1, pixelWidth: 1, pixelHeight: 1, categories: [])],
            screenshotIDs: ["shot"],
            livePhotoIDs: ["live"],
            skippedImageCount: 0
        )
        let updated = result.removingAssetIDs(["one", "two", "video", "shot", "live"])

        #expect(updated.similarImageGroups.isEmpty)
        #expect(updated.videoIDs.isEmpty)
        #expect(updated.screenshotIDs.isEmpty)
        #expect(updated.livePhotoIDs.isEmpty)
    }

    @Test("Device storage fractions remain finite for extreme capacities")
    func deviceStorageExtremesRemainFinite() {
        let negative = DeviceStorageSnapshot(totalBytes: -1, availableBytes: Int64.max)
        let full = DeviceStorageSnapshot(totalBytes: Int64.max, availableBytes: 0)

        #expect(negative.usedBytes == 0)
        #expect(negative.usedFraction == 0)
        #expect(full.usedFraction == 1)
        #expect(full.usedFraction.isFinite)
    }
}
