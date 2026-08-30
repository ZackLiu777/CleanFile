//
//  AppStateStore.swift
//  CleanMyIPhone
//

//
//  文件职责：负责 AppState 状态的持久化与恢复。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 定义 `MediaStateSnapshot` 的值语义数据与相关行为。
nonisolated struct MediaStateSnapshot: Codable, Sendable {
    let result: MediaClassificationResult
    let isPartial: Bool
}

/// 定义 `FileStateSnapshot` 的值语义数据与相关行为。
nonisolated struct FileStateSnapshot: Codable, Sendable {
    let directoryBookmark: Data
    let selectedDirectoryName: String
    let files: [ScannedFile]
    let skippedFileCount: Int
}

/// 使用 Actor 隔离 `AppStateStore` 的可变状态，确保并发访问安全。
actor AppStateStore {
    static let shared = AppStateStore()

    /// 定义 `SnapshotName` 使用的有限状态或选项集合。
    private enum SnapshotName: String {
        case media = "media-state.json"
        case files = "file-state.json"
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directoryURL: URL

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        directoryURL = applicationSupport.appendingPathComponent(
            "CleanMyIPhoneState",
            isDirectory: true
        )
    }

    /// 加载 `loadMediaState` 所需的数据，并将结果转换为当前层可消费的状态。
    func loadMediaState() -> MediaStateSnapshot? {
        load(MediaStateSnapshot.self, name: .media)
    }

    /// 持久化 `saveMediaState` 对应的数据，并保持后续恢复所需的信息完整。
    func saveMediaState(_ snapshot: MediaStateSnapshot?) {
        save(snapshot, name: .media)
    }

    /// 加载 `loadFileState` 所需的数据，并将结果转换为当前层可消费的状态。
    func loadFileState() -> FileStateSnapshot? {
        let interval = StoragePerformance.begin("Storage Snapshot Load")
        defer { StoragePerformance.end("Storage Snapshot Load", id: interval) }
        return load(FileStateSnapshot.self, name: .files)
    }

    /// 持久化 `saveFileState` 对应的数据，并保持后续恢复所需的信息完整。
    func saveFileState(_ snapshot: FileStateSnapshot?) {
        save(snapshot, name: .files)
    }

    /// 加载 `load` 所需的数据，并将结果转换为当前层可消费的状态。
    private func load<T: Decodable>(_ type: T.Type, name: SnapshotName) -> T? {
        let url = directoryURL.appendingPathComponent(name.rawValue)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    /// 持久化 `save` 对应的数据，并保持后续恢复所需的信息完整。
    private func save<T: Encodable>(_ value: T?, name: SnapshotName) {
        let fileManager = FileManager.default
        let url = directoryURL.appendingPathComponent(name.rawValue)
        guard let value else {
            try? fileManager.removeItem(at: url)
            return
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence failure must not interrupt scanning, analysis, or deletion.
        }
    }
}
