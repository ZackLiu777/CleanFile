//
//  文件职责：集中定义 MediaDateGrouping 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 定义 `MediaDatedAsset` 的值语义数据与相关行为。
nonisolated struct MediaDatedAsset: Hashable, Sendable {
    let id: String
    let creationDate: Date?
}

/// 定义 `MediaDateSection` 的值语义数据与相关行为。
nonisolated struct MediaDateSection: Identifiable, Hashable, Sendable {
    let id: String
    let day: Date?
    let assetIDs: [String]
}

/// 定义 `MediaDateSectionBuilder` 使用的有限状态或选项集合。
nonisolated enum MediaDateSectionBuilder {
    /// 封装 `sections` 对应的局部行为，供当前类型在统一入口下复用。
    static func sections(
        from assets: [MediaDatedAsset],
        calendar: Calendar = .current
    ) -> [MediaDateSection] {
        var knownDates: [Date: [MediaDatedAsset]] = [:]
        var unknownDates: [MediaDatedAsset] = []

        for asset in assets {
            guard let creationDate = asset.creationDate else {
                unknownDates.append(asset)
                continue
            }
            knownDates[calendar.startOfDay(for: creationDate), default: []].append(asset)
        }

        var sections = knownDates.keys.sorted(by: >).map { day in
            MediaDateSection(
                id: "day-\(day.timeIntervalSinceReferenceDate)",
                day: day,
                assetIDs: sorted(knownDates[day, default: []])
            )
        }

        if !unknownDates.isEmpty {
            sections.append(MediaDateSection(
                id: "unknown-date",
                day: nil,
                assetIDs: sorted(unknownDates)
            ))
        }
        return sections
    }

    /// 封装 `sorted` 对应的局部行为，供当前类型在统一入口下复用。
    private static func sorted(_ assets: [MediaDatedAsset]) -> [String] {
        assets.sorted { lhs, rhs in
            switch (lhs.creationDate, rhs.creationDate) {
            case let (left?, right?) where left != right:
                left > right
            default:
                lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
        }.map(\.id)
    }
}
