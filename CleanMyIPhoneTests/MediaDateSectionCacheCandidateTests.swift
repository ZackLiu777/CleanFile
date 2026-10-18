import Foundation
import Testing
@testable import CleanMyIPhone

@Suite("Media date section cache candidate")
struct MediaDateSectionCacheCandidateTests {
    @Test("Candidate preserves baseline dates, unknown dates, ties and identifier order")
    func matchesBaseline() {
        let calendar = utcCalendar
        let inputs: [[MediaDatedAsset]] = [
            [],
            [MediaDatedAsset(id: "only", creationDate: nil)],
            [
                MediaDatedAsset(id: "item-10", creationDate: referenceDate),
                MediaDatedAsset(id: "item-2", creationDate: referenceDate),
                MediaDatedAsset(id: "yesterday", creationDate: referenceDate.addingTimeInterval(-86_400)),
                MediaDatedAsset(id: "unknown-b", creationDate: nil),
                MediaDatedAsset(id: "unknown-a", creationDate: nil)
            ]
        ]

        for (generation, input) in inputs.enumerated() {
            var cache = MediaDateSectionCacheCandidate()
            let revision = MediaDateSectionCacheCandidate.Revision(
                sourceID: "screenshots",
                generation: UInt64(generation)
            )
            let actual = cache.sections(revision: revision, calendar: calendar) { input }
            let expected = MediaDateSectionBuilder.sections(from: input, calendar: calendar)
            #expect(actual == expected)
        }
    }

    @Test("Repeated selection-only reads do not reconstruct the metadata input")
    func repeatedReadsReuseSnapshot() {
        var cache = MediaDateSectionCacheCandidate()
        let revision = MediaDateSectionCacheCandidate.Revision(sourceID: "screenshots", generation: 1)
        let input = [MediaDatedAsset(id: "one", creationDate: referenceDate)]
        var inputReads = 0
        var selectedIDs = Set<String>()
        let first = cache.sections(revision: revision, calendar: utcCalendar) {
            inputReads += 1
            return input
        }

        for _ in 0 ..< 10 {
            if !selectedIDs.insert("one").inserted { selectedIDs.remove("one") }
            let next = cache.sections(revision: revision, calendar: utcCalendar) {
                inputReads += 1
                return input
            }
            #expect(next == first)
        }

        #expect(inputReads == 1)
        #expect(selectedIDs.isEmpty)
    }

    @Test("Generation and source changes invalidate input even with unchanged item count")
    func revisionChangesInvalidate() {
        var cache = MediaDateSectionCacheCandidate()
        var inputReads = 0
        let oldInput = [MediaDatedAsset(id: "old", creationDate: referenceDate)]
        let newInput = [MediaDatedAsset(id: "new", creationDate: referenceDate.addingTimeInterval(86_400))]
        let revisions = [
            MediaDateSectionCacheCandidate.Revision(sourceID: "screenshots", generation: 1),
            MediaDateSectionCacheCandidate.Revision(sourceID: "screenshots", generation: 2),
            MediaDateSectionCacheCandidate.Revision(sourceID: "screenshots", generation: 3),
            MediaDateSectionCacheCandidate.Revision(sourceID: "screenshots", generation: 4),
            MediaDateSectionCacheCandidate.Revision(sourceID: "videos", generation: 4)
        ]
        let inputs = [
            oldInput,
            [MediaDatedAsset(id: "old", creationDate: referenceDate.addingTimeInterval(86_400))],
            [],
            newInput,
            oldInput
        ]
        for (index, revision) in revisions.enumerated() {
            let input = inputs[index]
            let actual = cache.sections(revision: revision, calendar: utcCalendar) {
                inputReads += 1
                return input
            }
            #expect(actual == MediaDateSectionBuilder.sections(from: input, calendar: utcCalendar))
        }
        #expect(inputReads == revisions.count)
    }

    @Test("Calendar, timezone, locale and week settings all invalidate the cache")
    func calendarChangesInvalidate() throws {
        var losAngeles = utcCalendar
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var differentLocale = losAngeles
        differentLocale.locale = Locale(identifier: "zh-Hans_CN")
        var differentWeek = differentLocale
        differentWeek.firstWeekday = differentWeek.firstWeekday == 1 ? 2 : 1
        var differentMinimumDays = differentWeek
        differentMinimumDays.minimumDaysInFirstWeek = differentMinimumDays.minimumDaysInFirstWeek == 4 ? 1 : 4
        var differentIdentifier = Calendar(identifier: .buddhist)
        differentIdentifier.timeZone = losAngeles.timeZone

        let input = [
            MediaDatedAsset(id: "before-midnight", creationDate: Date(timeIntervalSince1970: 1_773_035_999)),
            MediaDatedAsset(id: "after-midnight", creationDate: Date(timeIntervalSince1970: 1_773_036_001))
        ]
        var cache = MediaDateSectionCacheCandidate()
        var inputReads = 0
        let revision = MediaDateSectionCacheCandidate.Revision(sourceID: "screenshots", generation: 1)
        let calendars = [
            utcCalendar, losAngeles, differentLocale, differentWeek,
            differentMinimumDays, differentIdentifier
        ]
        for calendar in calendars {
            let actual = cache.sections(revision: revision, calendar: calendar) {
                inputReads += 1
                return input
            }
            #expect(actual == MediaDateSectionBuilder.sections(from: input, calendar: calendar))
        }
        #expect(inputReads == calendars.count)
    }

    @Test("Daylight-saving boundaries produce exactly the baseline sections")
    func daylightSavingBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let springBefore: Date? = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30)
        )
        let springAfter: Date? = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30)
        )
        let fallBefore: Date? = utcCalendar.date(
            from: DateComponents(year: 2026, month: 11, day: 1, hour: 8, minute: 30)
        )
        let fallAfter: Date? = utcCalendar.date(
            from: DateComponents(year: 2026, month: 11, day: 1, hour: 9, minute: 30)
        )
        guard let springBefore, let springAfter, let fallBefore, let fallAfter else {
            Issue.record("Unable to construct daylight-saving comparison dates")
            return
        }
        let input = [
            MediaDatedAsset(id: "spring-before", creationDate: springBefore),
            MediaDatedAsset(id: "spring-after", creationDate: springAfter),
            MediaDatedAsset(id: "fall-before", creationDate: fallBefore),
            MediaDatedAsset(id: "fall-after", creationDate: fallAfter)
        ]
        var cache = MediaDateSectionCacheCandidate()
        let actual = cache.sections(
            revision: .init(sourceID: "screenshots", generation: 1),
            calendar: calendar
        ) { input }
        #expect(actual == MediaDateSectionBuilder.sections(from: input, calendar: calendar))
    }

    @Test("Mutating returned arrays does not mutate cached sections")
    func returnedArraysKeepValueSemantics() {
        var cache = MediaDateSectionCacheCandidate()
        let revision = MediaDateSectionCacheCandidate.Revision(sourceID: "screenshots", generation: 1)
        let input = [MediaDatedAsset(id: "one", creationDate: referenceDate)]
        var returned = cache.sections(revision: revision, calendar: utcCalendar) { input }
        returned[0] = MediaDateSection(id: "changed", day: nil, assetIDs: ["changed"])
        returned.append(MediaDateSection(id: "extra", day: nil, assetIDs: []))

        let next = cache.sections(revision: revision, calendar: utcCalendar) { input }
        #expect(next == MediaDateSectionBuilder.sections(from: input, calendar: utcCalendar))
        #expect(returned != next)
    }

    @Test("Explicit invalidation rebuilds the same revision")
    func explicitInvalidation() {
        var cache = MediaDateSectionCacheCandidate()
        let revision = MediaDateSectionCacheCandidate.Revision(sourceID: "screenshots", generation: 1)
        var inputReads = 0
        for round in 0 ..< 2 {
            if round == 1 { cache.invalidate() }
            _ = cache.sections(revision: revision, calendar: utcCalendar) {
                inputReads += 1
                return []
            }
        }
        #expect(inputReads == 2)
    }

    private var referenceDate: Date { Date(timeIntervalSince1970: 1_773_036_000) }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
