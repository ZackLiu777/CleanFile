//
//  快速清理选择索引
//
//  按分类成员位掩码预计算数量和预估字节，供重复选择查询复用。
//  同一资源属于多个已选分类时只计一次；资源或估算发生变化后须重建。
//

import Foundation

/// Immutable summary index prepared off MainActor for repeated quick-clean selection queries.
///
/// Category positions are the bits in a selection mask (at most nine categories).
/// Inputs must be one snapshot: use the same batch-calibrated Int64 byte estimates
/// as the existing estimatedByteCount reduction. Rebuild when category membership,
/// asset availability, exact sizes, or size calibration changes; queries do not
/// consult PhotoKit or automatically update estimates.
nonisolated struct MediaQuickCleanSelectionIndex: Sendable {
    /// 一个选择组合对应的去重资源数与预估字节数。
    struct Summary: Equatable, Sendable {
        let selectedCount: Int
        let estimatedByteCount: Int64

        static let empty = Summary(selectedCount: 0, estimatedByteCount: 0)
    }

    /// 索引不能表示过多分类，或字节汇总溢出时返回的构建错误。
    enum BuildError: Error, Equatable {
        case tooManyCategories
        case byteCountOverflow
    }

    let categoryCount: Int
    let uniqueAssetCount: Int
    private let validSelectionMask: UInt16
    private let summaries: [Summary]

    var storedSelectionCount: Int { summaries.count }

    /// 根据分类成员关系建立全部选择组合的汇总，周期性检查取消并检测字节溢出。
    init(
        categoryAssetIDs: [Set<String>],
        estimatedByteCountsByID: [String: Int64]
    ) throws {
        guard categoryAssetIDs.count <= 9 else {
            throw BuildError.tooManyCategories
        }

        categoryCount = categoryAssetIDs.count
        let selectionCount = 1 << categoryCount
        validSelectionMask = UInt16(selectionCount - 1)

        var membershipByID: [String: UInt16] = [:]
        var processed = 0
        for (categoryIndex, assetIDs) in categoryAssetIDs.enumerated() {
            let categoryMask = UInt16(1 << categoryIndex)
            for id in assetIDs {
                if processed.isMultiple(of: 256) { try Task.checkCancellation() }
                processed += 1
                membershipByID[id, default: 0] |= categoryMask
            }
        }
        uniqueAssetCount = membershipByID.count

        var combinations = Array(repeating: Summary.empty, count: selectionCount)
        for (id, membershipMask) in membershipByID {
            if processed.isMultiple(of: 256) { try Task.checkCancellation() }
            processed += 1
            let index = Int(membershipMask)
            let previous = combinations[index]
            let bytes = previous.estimatedByteCount.addingReportingOverflow(
                estimatedByteCountsByID[id] ?? 0
            )
            guard !bytes.overflow else { throw BuildError.byteCountOverflow }
            combinations[index] = Summary(
                selectedCount: previous.selectedCount + 1,
                estimatedByteCount: bytes.partialValue
            )
        }

        // A resource contributes once when any selected category intersects its
        // membership mask. This preserves overlap semantics without retaining IDs
        // in the index or allocating a union Set on each view update.
        var result = Array(repeating: Summary.empty, count: selectionCount)
        for selectedMask in 1 ..< selectionCount {
            var count = 0
            var bytes: Int64 = 0
            for membershipMask in 1 ..< selectionCount where selectedMask & membershipMask != 0 {
                let combination = combinations[membershipMask]
                let nextBytes = bytes.addingReportingOverflow(combination.estimatedByteCount)
                guard !nextBytes.overflow else { throw BuildError.byteCountOverflow }
                count += combination.selectedCount
                bytes = nextBytes.partialValue
            }
            result[selectedMask] = Summary(selectedCount: count, estimatedByteCount: bytes)
        }
        summaries = result
    }

    /// O(1) after construction; bits outside the category snapshot have no effect.
    func summary<Mask: BinaryInteger>(forSelectionMask selectedMask: Mask) -> Summary {
        summaries[Int(UInt16(truncatingIfNeeded: selectedMask) & validSelectionMask)]
    }

    /// 查询单一分类的汇总；无效索引返回空汇总。
    func summary(forCategoryAt index: Int) -> Summary {
        guard (0 ..< categoryCount).contains(index) else { return .empty }
        return summary(forSelectionMask: UInt16(1 << index))
    }
}
