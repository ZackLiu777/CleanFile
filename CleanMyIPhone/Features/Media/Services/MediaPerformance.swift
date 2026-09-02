import os.signpost

/// Points-of-interest intervals for profiling PhotoKit work on a real device.
/// Names and aggregate timings are recorded; asset identifiers and user media
/// metadata are intentionally excluded.
nonisolated enum MediaPerformance {
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
}
