//
//  StoragePerformance.swift
//  CleanMyIPhone
//

import os.signpost

/// Shared points-of-interest intervals for true-device storage profiling.
/// Signposts are intentionally aggregation-only and never contain file names,
/// paths, bookmarks, or other user data.
nonisolated enum StoragePerformance {
    private static let log = OSLog(
        subsystem: "ZaneLiao.CleanMyIPhone",
        category: .pointsOfInterest
    )

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
