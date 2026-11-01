//
//  媒体分析边界
//
//  覆盖日期分组、视频分类阈值和资源移除后的分类结果。
//  还检查极端容量输入下的存储占比。
//  验证同日排序、未知日期、阈值包含边界和多个视频子类型同时生效。
//  资源和容量均为内存构造的值，不读取相册。
//

import Foundation
import Photos
import Testing
@testable import CleanMyIPhone

/// 验证日期、视频元数据和分类结果的边界输入。
@Suite("Media analysis edge cases")
struct MediaEdgeCaseTests {
    /// 没有资源时不创建空日期分组。
    @Test("Empty date input produces no sections")
    func emptyDateInputIsEmpty() {
        #expect(MediaDateSectionBuilder.sections(from: []).isEmpty)
    }

    /// 固定 UTC 日历，验证同一天早晚资源归入同组且较晚资源排在前面。
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

    /// 缺失日期资源应放在已知日期之后，并按标识稳定排序。
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

    /// 负时长和零尺寸且无子类型时，不应产生视频分类。
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

    /// 核对视频时长与尺寸恰好达到阈值时仍属于对应分类。
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

    /// 录屏、高帧率和延时摄影子类型可以同时保留在一个结果中。
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

    /// 移除所有资源后不能留下空相似组或过期标识。
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

    /// 检查负总容量和最大整型容量下的已用量与占比边界。
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
