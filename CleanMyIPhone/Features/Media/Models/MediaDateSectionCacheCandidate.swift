//
//  日期分组缓存
//
//  以相册修订号和日历环境作为缓存键，避免详情页重复构造日期分组。
//  调用方必须在资源成员、日期或可用性变化时推进 generation；界面选择变化不影响缓存。
//

import Foundation
import Combine

/// Reuses date sections until asset membership, metadata or calendar settings change.
nonisolated struct MediaDateSectionCacheCandidate: Sendable {
    /// 区分输入来源与修订代次；成员或日期元数据发生变化时调用方须更新代次。
    struct Revision: Equatable, Sendable {
        let sourceID: String
        let generation: UInt64
    }

    /// 将修订号和日历环境共同作为缓存键，防止地区或时区变化后误用旧分组。
    private struct Key: Equatable, Sendable {
        let revision: Revision
        let calendar: Calendar
        let timeZoneIdentifier: String
        let calendarLocaleIdentifier: String?
        let firstWeekday: Int
        let minimumDaysInFirstWeek: Int
        let comparisonLocale: Locale

        /// 快照化修订号与日历的关键设置，避免自动更新环境使旧键随之改变。
        init(revision: Revision, calendar: Calendar) {
            self.revision = revision
            self.calendar = calendar
            // Capture individual settings as values too: autoupdating calendars
            // must not make an old cache key silently follow a new environment.
            timeZoneIdentifier = calendar.timeZone.identifier
            calendarLocaleIdentifier = calendar.locale?.identifier
            firstWeekday = calendar.firstWeekday
            minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
            comparisonLocale = .current
        }
    }

    private var key: Key?
    private var cachedSections: [MediaDateSection] = []
    private(set) var orderedAssetIDs: [String] = []
    private(set) var unsectioned: [MediaDateSection] = []

    /// `generation` must change when membership, IDs, creation dates, or their
    /// availability changes. Reusing a revision for different input is invalid.
    /// Source IDs distinguish categories/libraries that can share a generation.
    /// Selection and presentation-only changes deliberately do not enter the key.
    ///
    /// The closure is lazy so a hit avoids rebuilding the input metadata array.
    /// Returned arrays share immutable storage through Swift copy-on-write.
    mutating func sections(
        revision: Revision,
        calendar: Calendar = .current,
        assets: () -> [MediaDatedAsset]
    ) -> [MediaDateSection] {
        let requestedKey = Key(revision: revision, calendar: calendar)
        if key == requestedKey {
            return cachedSections
        }

        let sections = MediaDateSectionBuilder.sections(from: assets(), calendar: calendar)
        cachedSections = sections
        orderedAssetIDs = sections.flatMap(\.assetIDs)
        unsectioned = [MediaDateSection(id: "all-media", day: nil, assetIDs: orderedAssetIDs)]
        key = requestedKey
        return sections
    }

    /// Use for an explicit environment reset, including a locale preference or
    /// time-zone rules update that does not change the captured identifiers.
    mutating func invalidate() {
        key = nil
        cachedSections = []
        orderedAssetIDs = []
        unsectioned = []
    }
}

/// Scoped to a detail view so cached sections are released when that view goes away.
@MainActor
final class MediaDateSectionStore: ObservableObject {
    private var cache = MediaDateSectionCacheCandidate()
    private var assetIDs: [String] = []
    private var libraryRevision: UInt64?
    private var generation: UInt64 = 0

    /// 与日期分组同步更新，避免每次选择或容量刷新都展开整个分类。
    var orderedAssetIDs: [String] { cache.orderedAssetIDs }
    var unsectioned: [MediaDateSection] { cache.unsectioned }

    /// 资源标识或相册修订号变化时推进代次；缓存命中时不调用资源构造闭包。
    func sections(assetIDs: [String], libraryRevision: UInt64,
                  assets: () -> [MediaDatedAsset]) -> [MediaDateSection] {
        if self.libraryRevision != libraryRevision || self.assetIDs != assetIDs {
            self.assetIDs = assetIDs
            self.libraryRevision = libraryRevision
            generation &+= 1
        }
        return cache.sections(revision: .init(sourceID: "media-detail", generation: generation), assets: assets)
    }
}
