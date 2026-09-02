//
//  ConversionPerformance.swift
//  ImageFormatConversionKit
//
//  Instruments intervals for the expensive conversion pipeline stages.
//  Labels deliberately contain no file names or paths.
//

import Foundation
import os

enum ConversionPerformance {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "ImageFormatConversionKit",
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
