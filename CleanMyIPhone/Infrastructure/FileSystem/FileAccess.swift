//
//  文件访问作用域
//
//  定义在受控访问生命周期中执行文件操作的接口及其实现。
//  安全作用域在操作结束或抛错时均释放；不受限实现供无需授权的调用场景使用。
//

//
//  FileAccess.swift
//  CleanMyIPhone
//

import Foundation

/// 抽象单次同步文件操作的访问生命周期，让扫描逻辑无需决定授权获取方式。
protocol FileAccessProviding: Sendable {
    /// 在 URL 的访问期内执行闭包，返回闭包结果并向调用方传播错误。
    /// 闭包结束后不得假设安全作用域仍然有效。
    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T
}

/// 获取系统安全作用域后执行操作，无论成功或抛错都在退出时释放。
struct SecurityScopedFileAccess: FileAccessProviding, Sendable {
    /// 此实现不保存访问状态；每次操作单独获取作用域。
    nonisolated init() {}

    /// 获取失败时抛出安全作用域错误；闭包结束或抛错时均释放已获取的作用域。
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

/// 直接执行闭包的实现，适用于本身无需安全作用域的文件访问场景。
struct UnrestrictedFileAccess: FileAccessProviding, Sendable {
    /// 此实现不保存访问状态，也不请求安全作用域。
    nonisolated init() {}

    /// 直接执行闭包并传播其返回值或错误，由调用方保证文件本身可访问。
    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        try operation()
    }
}
