//
//  媒体日期分组
//
//  按传入日历将资源归入日期区段，并为缺失日期的资源保留单独区段。
//  日期和同日项目均采用稳定排序，便于列表刷新时保持一致的展示。
//

//
//  文件职责：集中定义 MediaDateGrouping 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 分组所需的资源标识与可选创建日期；不持有 PhotoKit 资源或图片内容。
nonisolated struct MediaDatedAsset: Hashable, Sendable {
    let id: String
    let creationDate: Date?
}

/// 一天或未知日期对应的有序资源标识集合。
nonisolated struct MediaDateSection: Identifiable, Hashable, Sendable {
    let id: String
    let day: Date?
    let assetIDs: [String]
}

/// 按调用方提供的日历构造稳定的媒体日期区段。
nonisolated enum MediaDateSectionBuilder {
    /// 按日历中的一天分组并按日期倒序排列，缺失日期的资源放在独立末尾区段。
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

    /// 组内优先按创建时间倒序，同时间或缺失时间时按本地化标识排序。
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
