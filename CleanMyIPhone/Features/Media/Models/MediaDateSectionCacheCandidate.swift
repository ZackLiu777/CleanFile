import Foundation
import Combine

/// Reuses date sections until asset membership, metadata or calendar settings change.
nonisolated struct MediaDateSectionCacheCandidate: Sendable {
    struct Revision: Equatable, Sendable {
        let sourceID: String
        let generation: UInt64
    }

    private struct Key: Equatable, Sendable {
        let revision: Revision
        let calendar: Calendar
        let timeZoneIdentifier: String
        let calendarLocaleIdentifier: String?
        let firstWeekday: Int
        let minimumDaysInFirstWeek: Int
        let comparisonLocale: Locale

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
        key = requestedKey
        return sections
    }

    /// Use for an explicit environment reset, including a locale preference or
    /// time-zone rules update that does not change the captured identifiers.
    mutating func invalidate() {
        key = nil
        cachedSections = []
    }
}

/// Scoped to a detail view so cached sections are released when that view goes away.
@MainActor
final class MediaDateSectionStore: ObservableObject {
    private var cache = MediaDateSectionCacheCandidate()
    private var assetIDs: [String] = []
    private var libraryRevision: UInt64?
    private var generation: UInt64 = 0

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
