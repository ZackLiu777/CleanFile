import Foundation

nonisolated struct MediaDatedAsset: Hashable, Sendable {
    let id: String
    let creationDate: Date?
}

nonisolated struct MediaDateSection: Identifiable, Hashable, Sendable {
    let id: String
    let day: Date?
    let assetIDs: [String]
}

nonisolated enum MediaDateSectionBuilder {
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
