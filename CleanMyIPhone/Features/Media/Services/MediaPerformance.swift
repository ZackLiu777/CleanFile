//
//  媒体性能测量
//
//  为媒体处理创建和结束系统性能区间，便于真机分析耗时。
//  记录静态名称及聚合时间，不写入资源标识或用户媒体元数据。
//

import os.signpost

/// Points-of-interest intervals for profiling PhotoKit work on a real device.
/// Names and aggregate timings are recorded; asset identifiers and user media
/// metadata are intentionally excluded.
nonisolated enum MediaPerformance {
    private static let log = OSLog(
        subsystem: "ZaneLiao.CleanMyIPhone",
        category: .pointsOfInterest
    )

    /// 开始具名性能区间并返回标识；调用方应使用相同名称和标识结束区间。
    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    /// 结束与标识对应的性能区间。
    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
