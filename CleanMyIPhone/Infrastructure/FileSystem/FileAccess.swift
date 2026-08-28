//
//  FileAccess.swift
//  CleanMyIPhone
//

//
//  文件职责：集中定义 FileAccess 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 定义 `FileAccessProviding` 必须提供的统一能力与调用约束。
protocol FileAccessProviding: Sendable {
    /// 封装 `withAccess` 对应的局部行为，供当前类型在统一入口下复用。
    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T
}

/// 定义 `SecurityScopedFileAccess` 的值语义数据与相关行为。
struct SecurityScopedFileAccess: FileAccessProviding, Sendable {
    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    nonisolated init() {}

    /// 封装 `withAccess` 对应的局部行为，供当前类型在统一入口下复用。
    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else {
            throw FileScanError.securityScopeUnavailable
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        return try operation()
    }
}

/// 定义 `UnrestrictedFileAccess` 的值语义数据与相关行为。
struct UnrestrictedFileAccess: FileAccessProviding, Sendable {
    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    nonisolated init() {}

    /// 封装 `withAccess` 对应的局部行为，供当前类型在统一入口下复用。
    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        try operation()
    }
}
