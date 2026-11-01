//
//  存储性能测量
//
//  使用系统 signpost 标记存储处理的区间和事件，供真机性能分析。
//  只记录静态名称和聚合信息，不记录文件名、路径或授权书签。
//

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

    /// 开始具名性能区间，返回供结束操作配对的标识。
    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    /// 结束对应的性能区间。
    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    /// 记录不含用户数据的瞬时性能事件。
    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
