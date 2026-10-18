import Dispatch
import Foundation
import Testing
@testable import CleanMyIPhone

@Suite("Quick-clean selection index candidate")
struct MediaQuickCleanSelectionIndexTests {
    @Test("Every category combination matches the retained union and reduction")
    func allSelectionCombinationsMatchBaseline() throws {
        let categories: [Set<String>] = [
            ["similar", "overlap", "missing"],
            ["screenshot", "overlap", "keeper"],
            ["video", "recording"],
            ["live", "overlap"],
            ["recording"],
            ["video"],
            ["video", "recording"],
            []
        ]
        let estimates: [String: Int64] = [
            "similar": 100,
            "overlap": 200,
            "screenshot": 300,
            "keeper": 400,
            "video": 500,
            "recording": 600,
            "live": 700
        ]
        let baseline = LegacyQuickCleanSelectionBaseline(categories: categories, estimates: estimates)
        let index = try MediaQuickCleanSelectionIndex(
            categoryAssetIDs: categories,
            estimatedByteCountsByID: estimates
        )

        for mask in UInt16.zero ... UInt16(UInt8.max) {
            let selection = QuickCleanSelection(mask: UInt8(mask), categoryCount: categories.count)
            #expect(index.summary(forSelectionMask: selection.mask) == baseline.summary(for: selection))
        }
        for category in categories.indices {
            #expect(index.summary(forCategoryAt: category) == baseline.summary(
                for: QuickCleanSelection(mask: UInt8(1 << category), categoryCount: categories.count)
            ))
        }
        #expect(index.summary(forCategoryAt: -1) == .empty)
        #expect(index.summary(forCategoryAt: 8) == .empty)
        #expect(index.uniqueAssetCount == 8)
    }

    @Test("Empty snapshots and out-of-snapshot selection bits remain empty")
    func emptyAndUnavailableCategories() throws {
        let empty = try MediaQuickCleanSelectionIndex(categoryAssetIDs: [], estimatedByteCountsByID: [:])
        #expect(empty.summary(forSelectionMask: UInt16.max) == .empty)
        #expect(empty.storedSelectionCount == 1)

        let index = try MediaQuickCleanSelectionIndex(
            categoryAssetIDs: [["available", "missing"]],
            estimatedByteCountsByID: ["available": 0, "unclassified": 900]
        )
        #expect(index.summary(forSelectionMask: 0b1000_0000) == .empty)
        #expect(index.summary(forSelectionMask: UInt16.max) == .init(selectedCount: 2, estimatedByteCount: 0))
    }

    @Test("Signed Int64 inputs retain their value without clamping or Double conversion")
    func signedAndLargeEstimates() throws {
        let categories: [Set<String>] = [["large", "negative"], ["negative", "zero"]]
        let estimates: [String: Int64] = ["large": 9_007_199_254_740_993, "negative": -7, "zero": 0]
        let baseline = LegacyQuickCleanSelectionBaseline(categories: categories, estimates: estimates)
        let index = try MediaQuickCleanSelectionIndex(
            categoryAssetIDs: categories,
            estimatedByteCountsByID: estimates
        )
        for mask in [UInt8(0), 1, 2, 3] {
            let selection = QuickCleanSelection(mask: mask, categoryCount: categories.count)
            #expect(index.summary(forSelectionMask: mask) == baseline.summary(for: selection))
        }
    }

    @Test("Ninth category participates in selection without truncating its mask")
    func ninthCategorySelection() throws {
        var categories = Array(repeating: Set<String>(), count: 9)
        categories[0] = ["shared"]
        categories[8] = ["shared", "other"]
        let index = try MediaQuickCleanSelectionIndex(
            categoryAssetIDs: categories,
            estimatedByteCountsByID: ["shared": 100, "other": 200]
        )
        #expect(index.summary(forSelectionMask: UInt16(256)) == .init(selectedCount: 2, estimatedByteCount: 300))
        #expect(index.summary(forSelectionMask: UInt16(257)) == .init(selectedCount: 2, estimatedByteCount: 300))
        #expect(index.summary(forCategoryAt: 8).selectedCount == 2)
    }

    @Test("Invalid construction reports failure instead of wrapping byte totals")
    func constructionLimitsAndOverflow() {
        #expect(throws: MediaQuickCleanSelectionIndex.BuildError.tooManyCategories) {
            try MediaQuickCleanSelectionIndex(
                categoryAssetIDs: Array(repeating: [], count: 10),
                estimatedByteCountsByID: [:]
            )
        }
        #expect(throws: MediaQuickCleanSelectionIndex.BuildError.byteCountOverflow) {
            try MediaQuickCleanSelectionIndex(
                categoryAssetIDs: [["maximum"], ["one"]],
                estimatedByteCountsByID: ["maximum": .max, "one": 1]
            )
        }
        #expect(throws: MediaQuickCleanSelectionIndex.BuildError.byteCountOverflow) {
            try MediaQuickCleanSelectionIndex(
                categoryAssetIDs: [["minimum", "negative"]],
                estimatedByteCountsByID: ["minimum": .min, "negative": -1]
            )
        }
    }

    @Test("Exact-size or availability changes require a new immutable snapshot")
    func changedSizeAndMembershipRebuild() throws {
        let originalCategories: [Set<String>] = [["estimated", "removed"], ["estimated"]]
        var estimates: [String: Int64] = ["estimated": 400, "removed": 100]
        let original = try MediaQuickCleanSelectionIndex(
            categoryAssetIDs: originalCategories,
            estimatedByteCountsByID: estimates
        )
        estimates["estimated"] = 237
        estimates["removed"] = nil
        let updatedCategories: [Set<String>] = [["estimated"], ["estimated", "new"]]
        estimates["new"] = 55
        let rebuilt = try MediaQuickCleanSelectionIndex(
            categoryAssetIDs: updatedCategories,
            estimatedByteCountsByID: estimates
        )

        #expect(original.summary(forSelectionMask: 3) == .init(selectedCount: 2, estimatedByteCount: 500))
        #expect(rebuilt.summary(forSelectionMask: 3) == .init(selectedCount: 2, estimatedByteCount: 292))
        let baseline = LegacyQuickCleanSelectionBaseline(categories: updatedCategories, estimates: estimates)
        #expect(rebuilt.summary(forSelectionMask: 3) == baseline.summary(
            for: QuickCleanSelection(mask: 3, categoryCount: updatedCategories.count)
        ))
    }
}

/// Core microbenchmarks use frozen per-ID Int64 estimates. They intentionally do
/// not time PhotoKit, calibration sample sorting, view rendering, or refreshing an
/// index after new exact sizes. A warm-query win cannot approve a production swap.
@Suite("Quick-clean selection performance candidate", .serialized)
struct MediaQuickCleanSelectionIndexPerformanceTests {
    @Test("Compare cold and repeated selection costs", arguments: [1_000, 10_000, 100_000])
    func compareWithRetainedBaseline(assetCount: Int) throws {
        let fixture = QuickCleanStatisticsFixture(assetCount: assetCount)
        let selections = [UInt8(1), 3, 7, 255, 0, 2, 6, 254, 15, 31, 63, 127, 128, 170, 85, 255]
            .map { QuickCleanSelection(mask: $0, categoryCount: fixture.categories.count) }
        let all = QuickCleanSelection(mask: .max, categoryCount: fixture.categories.count)

        for sample in 0 ..< 5 {
            // Cold comparison includes one equivalent full-selection summary on
            // both sides. Candidate initialization is never omitted here.
            let cold = try compare(sample: sample, baseline: {
                LegacyQuickCleanSelectionBaseline(categories: fixture.categories, estimates: fixture.estimates)
                    .summary(for: all)
            }, candidate: {
                let index = try MediaQuickCleanSelectionIndex(
                    categoryAssetIDs: fixture.categories,
                    estimatedByteCountsByID: fixture.estimates
                )
                return (index, index.summary(forSelectionMask: all.mask))
            })
            let coldEquivalent = cold.baseline == cold.candidate.1
            report(scenario: "cold-build", sample: sample, fixture: fixture,
                   baseline: cold.baselineNanoseconds, candidate: cold.candidateNanoseconds,
                   equivalent: coldEquivalent, queryCount: 1)
            #expect(coldEquivalent)

            let interactions = try compare(sample: sample, baseline: {
                let model = LegacyQuickCleanSelectionBaseline(categories: fixture.categories, estimates: fixture.estimates)
                return selections.map { model.summary(for: $0) }
            }, candidate: {
                let index = try MediaQuickCleanSelectionIndex(
                    categoryAssetIDs: fixture.categories,
                    estimatedByteCountsByID: fixture.estimates
                )
                return selections.map { index.summary(forSelectionMask: $0.mask) }
            })
            let interactionsEquivalent = interactions.baseline == interactions.candidate
            report(scenario: "interactions-total", sample: sample, fixture: fixture,
                   baseline: interactions.baselineNanoseconds, candidate: interactions.candidateNanoseconds,
                   equivalent: interactionsEquivalent, queryCount: selections.count)
            #expect(interactionsEquivalent)

            let warmBaseline = LegacyQuickCleanSelectionBaseline(categories: fixture.categories, estimates: fixture.estimates)
            let warmIndex = cold.candidate.0
            let warm = compare(sample: sample, baseline: {
                selections.map { warmBaseline.summary(for: $0) }
            }, candidate: {
                selections.map { warmIndex.summary(forSelectionMask: $0.mask) }
            })
            let warmEquivalent = warm.baseline == warm.candidate
            report(scenario: "warm-query", sample: sample, fixture: fixture,
                   baseline: warm.baselineNanoseconds, candidate: warm.candidateNanoseconds,
                   equivalent: warmEquivalent, queryCount: selections.count)
            #expect(warmEquivalent)
        }
    }

    private func compare<Baseline, Candidate>(
        sample: Int,
        baseline: () throws -> Baseline,
        candidate: () throws -> Candidate
    ) rethrows -> (
        baseline: Baseline, candidate: Candidate,
        baselineNanoseconds: UInt64, candidateNanoseconds: UInt64
    ) {
        if sample.isMultiple(of: 2) {
            let original = try measure(baseline)
            let proposed = try measure(candidate)
            return (original.value, proposed.value, original.nanoseconds, proposed.nanoseconds)
        } else {
            let proposed = try measure(candidate)
            let original = try measure(baseline)
            return (original.value, proposed.value, original.nanoseconds, proposed.nanoseconds)
        }
    }

    private func measure<Value>(_ body: () throws -> Value) rethrows -> (value: Value, nanoseconds: UInt64) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try body()
        return (value, DispatchTime.now().uptimeNanoseconds - start)
    }

    private func report(
        scenario: String, sample: Int, fixture: QuickCleanStatisticsFixture,
        baseline: UInt64, candidate: UInt64, equivalent: Bool, queryCount: Int
    ) {
        let report = QuickCleanCandidateTiming(
            experiment: "quick-clean-selection-index", scenario: scenario, sample: sample,
            assetCount: fixture.estimates.count, baselineNanoseconds: baseline,
            candidateNanoseconds: candidate, equivalent: equivalent, queryCount: queryCount,
            categoryCount: fixture.categories.count, indexedSelectionCount: 256,
            inputPreparationIncluded: false,
            scope: "frozen-byte-estimates-core-only"
        )
        do {
            let data = try JSONEncoder().encode(report)
            print("PERF_CANDIDATE_JSON \(String(decoding: data, as: UTF8.self))")
        } catch {
            Issue.record("Could not encode quick-clean performance report: \(error)")
        }
    }
}

/// Retained pre-index algorithm: selected-category Set union followed by a byte
/// reduction. Missing assets contribute zero bytes but remain selected IDs.
private struct LegacyQuickCleanSelectionBaseline {
    let categories: [Set<String>]
    let estimates: [String: Int64]

    func summary(for selection: QuickCleanSelection) -> MediaQuickCleanSelectionIndex.Summary {
        let selectedIDs = categories.enumerated()
            .filter { selection.categoryIndices.contains($0.offset) }
            .reduce(into: Set<String>()) { selected, category in
                selected.formUnion(category.element)
            }
        let bytes = selectedIDs.reduce(Int64.zero) { total, id in
            total + (estimates[id] ?? 0)
        }
        return .init(selectedCount: selectedIDs.count, estimatedByteCount: bytes)
    }
}

private struct QuickCleanSelection {
    let mask: UInt8
    let categoryIndices: Set<Int>

    init(mask: UInt8, categoryCount: Int) {
        self.mask = mask
        categoryIndices = Set((0 ..< categoryCount).filter { mask & UInt8(1 << $0) != 0 })
    }
}

private struct QuickCleanStatisticsFixture {
    let categories: [Set<String>]
    let estimates: [String: Int64]

    init(assetCount: Int) {
        var categories = Array(repeating: Set<String>(), count: 8)
        var estimates: [String: Int64] = [:]
        estimates.reserveCapacity(assetCount)
        for index in 0 ..< assetCount {
            let id = "synthetic-asset-\(index)"
            let membership = (index % 255) + 1
            estimates[id] = Int64((index * 7_919) % 8_000_000)
            for category in categories.indices where membership & (1 << category) != 0 {
                categories[category].insert(id)
            }
        }
        self.categories = categories
        self.estimates = estimates
    }
}

private struct QuickCleanCandidateTiming: Encodable {
    let experiment: String
    let scenario: String
    let sample: Int
    let assetCount: Int
    let baselineNanoseconds: UInt64
    let candidateNanoseconds: UInt64
    let equivalent: Bool
    let queryCount: Int
    let categoryCount: Int
    let indexedSelectionCount: Int
    let inputPreparationIncluded: Bool
    let scope: String

    enum CodingKeys: String, CodingKey {
        case experiment, scenario, sample, equivalent, scope
        case assetCount = "asset_count"
        case baselineNanoseconds = "baseline_ns"
        case candidateNanoseconds = "candidate_ns"
        case queryCount = "query_count"
        case categoryCount = "category_count"
        case indexedSelectionCount = "indexed_selection_count"
        case inputPreparationIncluded = "input_preparation_included"
    }
}
