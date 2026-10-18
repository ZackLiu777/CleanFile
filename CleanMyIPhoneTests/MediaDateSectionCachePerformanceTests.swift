import Dispatch
import Foundation
import Testing
@testable import CleanMyIPhone

/// CI comparisons report cold, warm, and complete interaction costs separately.
/// No timing assertion or automatic promotion changes the production baseline.
@Suite("Media date section cache performance candidate", .serialized)
struct MediaDateSectionCachePerformanceTests {
    @Test("Compare preserved builder and cache across dataset sizes")
    func compareDateSectionCandidate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let revision = MediaDateSectionCacheCandidate.Revision(sourceID: "performance-screenshots", generation: 1)

        for assetCount in [1_000, 10_000, 100_000] {
            // One deterministic fixture per size, outside all timed blocks. Both
            // implementations share it rather than rebuild or retain five copies.
            let assets = Self.fixture(count: assetCount)
            for sample in 0 ..< 5 {
                for scenario in Scenario.allCases {
                    let baseline: Measurement
                    let candidate: Measurement
                    if sample.isMultiple(of: 2) {
                        baseline = Self.baseline(assets: assets, calendar: calendar, scenario: scenario)
                        candidate = Self.candidate(
                            assets: assets, revision: revision, calendar: calendar, scenario: scenario
                        )
                    } else {
                        candidate = Self.candidate(
                            assets: assets, revision: revision, calendar: calendar, scenario: scenario
                        )
                        baseline = Self.baseline(assets: assets, calendar: calendar, scenario: scenario)
                    }
                    let equivalent = baseline.sections == candidate.sections
                        && baseline.checksum == candidate.checksum
                    let report = Comparison(
                        experiment: "media-date-section-cache",
                        scenario: scenario.rawValue,
                        sample: sample,
                        asset_count: assetCount,
                        baseline_ns: baseline.nanoseconds,
                        candidate_ns: candidate.nanoseconds,
                        equivalent: equivalent
                    )
                    let encoded = try JSONEncoder().encode(report)
                    print("PERF_CANDIDATE_JSON \(String(decoding: encoded, as: UTF8.self))")
                    #expect(equivalent)
                    #expect(baseline.sections.flatMap(\.assetIDs).count == assetCount)
                    let expectedCandidateBuilds = scenario == .warmQuery ? 0 : 1
                    #expect(candidate.inputBuilds == expectedCandidateBuilds)
                }
            }
        }
    }

    private enum Scenario: String, CaseIterable {
        case coldBuild = "cold-build"
        case warmQuery = "warm-query"
        case interactionsTotal = "interactions-total"

        var queryCount: Int { self == .interactionsTotal ? 5 : 1 }
    }

    private struct Measurement {
        let nanoseconds: UInt64
        let sections: [MediaDateSection]
        let checksum: Int
        let inputBuilds: Int
    }

    private struct Comparison: Encodable {
        let experiment: String
        let scenario: String
        let sample: Int
        let asset_count: Int
        let baseline_ns: UInt64
        let candidate_ns: UInt64
        let equivalent: Bool
    }

    private static func baseline(
        assets: [MediaDatedAsset],
        calendar: Calendar,
        scenario: Scenario
    ) -> Measurement {
        var lastSections: [MediaDateSection] = []
        var checksum = 0
        let started = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< scenario.queryCount {
            lastSections = MediaDateSectionBuilder.sections(from: assets, calendar: calendar)
            checksum &+= consumedValue(lastSections)
        }
        let duration = DispatchTime.now().uptimeNanoseconds - started
        return Measurement(
            nanoseconds: duration,
            sections: lastSections,
            checksum: checksum,
            inputBuilds: scenario.queryCount
        )
    }

    private static func candidate(
        assets: [MediaDatedAsset],
        revision: MediaDateSectionCacheCandidate.Revision,
        calendar: Calendar,
        scenario: Scenario
    ) -> Measurement {
        var preparedCache: MediaDateSectionCacheCandidate?
        if scenario == .warmQuery {
            var cache = MediaDateSectionCacheCandidate()
            _ = cache.sections(revision: revision, calendar: calendar) { assets }
            preparedCache = cache
        }
        var lastSections: [MediaDateSection] = []
        var checksum = 0
        var inputBuilds = 0
        // Cold and interaction-total include the initial cache build. Only the
        // separately labelled warm-query intentionally excludes initialization.
        let started = DispatchTime.now().uptimeNanoseconds
        var cache = preparedCache ?? MediaDateSectionCacheCandidate()
        for _ in 0 ..< scenario.queryCount {
            lastSections = cache.sections(revision: revision, calendar: calendar) {
                inputBuilds += 1
                return assets
            }
            checksum &+= consumedValue(lastSections)
        }
        let duration = DispatchTime.now().uptimeNanoseconds - started
        return Measurement(
            nanoseconds: duration,
            sections: lastSections,
            checksum: checksum,
            inputBuilds: inputBuilds
        )
    }

    private static func consumedValue(_ sections: [MediaDateSection]) -> Int {
        sections.count + (sections.first?.assetIDs.count ?? 0) + (sections.last?.assetIDs.count ?? 0)
    }

    private static func fixture(count: Int) -> [MediaDatedAsset] {
        let referenceDate = Date(timeIntervalSince1970: 1_773_036_000)
        return (0 ..< count).map { index in
            let permuted = (index * 7_919) % count
            return MediaDatedAsset(
                id: "asset-\(permuted)",
                creationDate: index.isMultiple(of: 31) ? nil
                    : referenceDate.addingTimeInterval(Double(permuted % 365) * 86_400 + Double(permuted % 73))
            )
        }
    }
}
