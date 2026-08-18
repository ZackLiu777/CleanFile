//
//  FileAccess.swift
//  CleanMyIPhone
//

import Foundation

protocol FileAccessProviding: Sendable {
    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T
}

struct SecurityScopedFileAccess: FileAccessProviding, Sendable {
    nonisolated init() {}

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

struct UnrestrictedFileAccess: FileAccessProviding, Sendable {
    nonisolated init() {}

    nonisolated func withAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        try operation()
    }
}
