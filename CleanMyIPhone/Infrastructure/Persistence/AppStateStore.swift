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

/// Stores verified PhotoKit resource sizes. Modification dates invalidate stale entries.
nonisolated struct MediaSizeIndexSnapshot: Codable, Sendable {
    let entries: [String: MediaSizeIndexEntry]
}

nonisolated struct MediaSizeIndexEntry: Codable, Sendable {
    let modificationDate: Date?
    let byteCount: Int64
}

/// 定义 `FileStateSnapshot` 的值语义数据与相关行为。
nonisolated struct FileStateSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 3

    let schemaVersion: Int?
    let directoryBookmark: Data
    let selectedDirectoryName: String
    let files: [PersistedScannedFile]
    let skippedFileCount: Int

    init(
        directoryBookmark: Data,
        selectedDirectoryName: String,
        files: [ScannedFile],
        skippedFileCount: Int
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.directoryBookmark = directoryBookmark
        self.selectedDirectoryName = selectedDirectoryName
        self.files = files.map(PersistedScannedFile.init)
        self.skippedFileCount = skippedFileCount
    }

    /// Builds large snapshots cooperatively so a superseded scan does not keep
    /// converting an obsolete index in the background.
    static func prepare(
        directoryBookmark: Data,
        selectedDirectoryName: String,
        files: [ScannedFile],
        skippedFileCount: Int
    ) -> FileStateSnapshot? {
        var persistedFiles: [PersistedScannedFile] = []
        persistedFiles.reserveCapacity(files.count)
        for (index, file) in files.enumerated() {
            if index.isMultiple(of: 256), Task.isCancelled { return nil }
            persistedFiles.append(PersistedScannedFile(file))
        }
        return FileStateSnapshot(
            directoryBookmark: directoryBookmark,
            selectedDirectoryName: selectedDirectoryName,
            persistedFiles: persistedFiles,
            skippedFileCount: skippedFileCount
        )
    }

    private init(
        directoryBookmark: Data,
        selectedDirectoryName: String,
        persistedFiles: [PersistedScannedFile],
        skippedFileCount: Int
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.directoryBookmark = directoryBookmark
        self.selectedDirectoryName = selectedDirectoryName
        files = persistedFiles
        self.skippedFileCount = skippedFileCount
    }

    var requiresRewrite: Bool {
        schemaVersion != Self.currentSchemaVersion
    }
}

/// A compact persisted file record. The absolute provider URL is intentionally
/// omitted because it is transient and is rebuilt from the root bookmark and
/// validated relative components during restoration.
nonisolated struct PersistedScannedFile: Codable, Hashable, Sendable {
    let name: String
    let relativePathComponents: [String]
    let category: FileCategory
    let byteCount: Int64
    let hasKnownByteCount: Bool
    let creationDate: Date?
    let modificationDate: Date?

    /// Compact keys materially reduce large indexes because these field names
    /// occur once for every file. Decoding still accepts the schema-v2 names.
    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case relativePathComponents = "p"
        case category = "c"
        case byteCount = "b"
        case hasKnownByteCount = "k"
        case creationDate = "cd"
        case modificationDate = "md"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case name
        case relativePathComponents
        case category
        case byteCount
        case hasKnownByteCount
        case creationDate
        case modificationDate
    }

    init(_ file: ScannedFile) {
        name = file.name
        relativePathComponents = file.relativePathComponents
        category = file.category
        byteCount = file.byteCount
        hasKnownByteCount = file.hasKnownByteCount
        creationDate = file.creationDate
        modificationDate = file.modificationDate
    }

    init(from decoder: Decoder) throws {
        let compact = try decoder.container(keyedBy: CodingKeys.self)
        if compact.contains(.name) {
            name = try compact.decode(String.self, forKey: .name)
            relativePathComponents = try compact.decode([String].self, forKey: .relativePathComponents)
            category = try compact.decode(FileCategory.self, forKey: .category)
            byteCount = try compact.decode(Int64.self, forKey: .byteCount)
            hasKnownByteCount = try compact.decode(Bool.self, forKey: .hasKnownByteCount)
            creationDate = try compact.decodeIfPresent(Date.self, forKey: .creationDate)
            modificationDate = try compact.decodeIfPresent(Date.self, forKey: .modificationDate)
            return
        }

        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        name = try legacy.decode(String.self, forKey: .name)
        relativePathComponents = try legacy.decode([String].self, forKey: .relativePathComponents)
        category = try legacy.decode(FileCategory.self, forKey: .category)
        byteCount = try legacy.decode(Int64.self, forKey: .byteCount)
        hasKnownByteCount = try legacy.decode(Bool.self, forKey: .hasKnownByteCount)
        creationDate = try legacy.decodeIfPresent(Date.self, forKey: .creationDate)
        modificationDate = try legacy.decodeIfPresent(Date.self, forKey: .modificationDate)
    }
}

/// Small dashboard cache loaded before the full file index. Keeping it in a
/// separate file lets the storage tab render without decoding tens of
/// thousands of file records first.
nonisolated struct StorageDashboardSnapshot: Codable, Sendable {
    let selectedDirectoryName: String
    let summary: StorageSummary
    let skippedFileCount: Int
}

/// 使用 Actor 隔离 `AppStateStore` 的可变状态，确保并发访问安全。
actor AppStateStore {
    static let shared = AppStateStore()

    /// 定义 `SnapshotName` 使用的有限状态或选项集合。
    private enum SnapshotName: String {
        case media = "media-state.json"
        case mediaSizes = "media-size-index.json"
        case files = "file-state.json"
        case fileDashboard = "file-dashboard.json"
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

    func loadMediaSizeIndex() -> MediaSizeIndexSnapshot? {
        load(MediaSizeIndexSnapshot.self, name: .mediaSizes)
    }

    func saveMediaSizeIndex(_ snapshot: MediaSizeIndexSnapshot?) {
        save(snapshot, name: .mediaSizes)
    }

    /// 加载 `loadFileState` 所需的数据，并将结果转换为当前层可消费的状态。
    func loadFileState() -> FileStateSnapshot? {
        let interval = StoragePerformance.begin("Storage Snapshot Load")
        defer { StoragePerformance.end("Storage Snapshot Load", id: interval) }
        return load(FileStateSnapshot.self, name: .files)
    }

    func saveFileState(_ snapshot: FileStateSnapshot?) {
        let interval = StoragePerformance.begin("Storage Snapshot Save")
        defer { StoragePerformance.end("Storage Snapshot Save", id: interval) }
        save(snapshot, name: .files)
    }

    func loadStorageDashboard() -> StorageDashboardSnapshot? {
        let interval = StoragePerformance.begin("Storage Dashboard Load")
        defer { StoragePerformance.end("Storage Dashboard Load", id: interval) }
        return load(StorageDashboardSnapshot.self, name: .fileDashboard)
    }

    func saveStorageDashboard(_ snapshot: StorageDashboardSnapshot?) {
        save(snapshot, name: .fileDashboard)
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
