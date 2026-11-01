//
//  为导入、编解码与提交等耗时阶段提供系统性能区间标记。
//  调用方使用相同名称和返回的标识配对开始、结束事件。
//  标记只使用静态名称，不包含用户文件名或路径。
//  导入与转换阶段使用这些标记在 Instruments 中观察耗时。
//  标记只辅助诊断，不改变任务调度，也不作为性能通过阈值。
//

//
//  ConversionPerformance.swift
//  ImageFormatConversionKit
//
//  Instruments intervals for the expensive conversion pipeline stages.
//  Labels deliberately contain no file names or paths.
//

import Foundation
import os

/// 用静态名称记录 Instruments 可查看的转换阶段区间。
enum ConversionPerformance {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "ImageFormatConversionKit",
        category: .pointsOfInterest
    )

    /// 开始区间并返回标识，供对应的结束事件配对。
    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    /// 结束指定标识对应的性能区间。
    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
