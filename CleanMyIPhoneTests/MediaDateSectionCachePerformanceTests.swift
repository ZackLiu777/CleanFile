//
//  日期分组缓存性能比较
//
//  比较不同规模下原始分组与缓存候选的工作量及输出。
//  该文件记录性能实验，不将具体耗时等同于设备性能保证。
//  区分首次构建、预热查询和包含初始化的多次交互，并检查分组与校验值一致。
//  每种规模共用确定性合成输入，轮换两条路径的计时顺序。
//

import Dispatch
import Foundation
import Testing
@testable import CleanMyIPhone

/// CI comparisons report cold, warm, and complete interaction costs separately.
/// No timing assertion or automatic promotion changes the production baseline.
/// 序列化比较分组缓存与原有构建路径的行为和耗时。
@Suite("Media date section cache performance candidate", .serialized)
struct MediaDateSectionCachePerformanceTests {
    /// 比较不同数据规模下原始分组与缓存路径，并消费结果以保证比较具有实际工作量。
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

    /// 区分冷构建、预热后单次查询和包含首次构建的交互总成本。
    private enum Scenario: String, CaseIterable {
        case coldBuild = "cold-build"
        case warmQuery = "warm-query"
        case interactionsTotal = "interactions-total"

        var queryCount: Int { self == .interactionsTotal ? 5 : 1 }
    }

    /// 保存单次路径的耗时、分组结果、消费校验值和输入构造次数。
    private struct Measurement {
        let nanoseconds: UInt64
        let sections: [MediaDateSection]
        let checksum: Int
        let inputBuilds: Int
    }

    /// 用于输出两种实现耗时及等价性的结构化实验记录。
    private struct Comparison: Encodable {
        let experiment: String
        let scenario: String
        let sample: Int
        let asset_count: Int
        let baseline_ns: UInt64
        let candidate_ns: UInt64
        let equivalent: Bool
    }

    /// 在计时区间内按场景重复执行原始分组，并累计消费结果。
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

    /// 仅在预热查询场景将首次构建排除在计时外，并统计缓存闭包调用次数。
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

    /// 消费首尾分组和总组数，使比较包含对结果的实际读取。
    private static func consumedValue(_ sections: [MediaDateSection]) -> Int {
        sections.count + (sections.first?.assetIDs.count ?? 0) + (sections.last?.assetIDs.count ?? 0)
    }

    /// 生成可重复的跨日期资源及少量缺失日期，供两个路径共享同一输入。
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
