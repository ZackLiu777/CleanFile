//
//  应用状态持久化
//
//  定义媒体、文件和存储概览快照，并在应用支持目录中读写 JSON。
//  文件记录保存相对路径而非临时绝对 URL；持久化失败不会中断扫描或删除。
//

//
//  AppStateStore.swift
//  CleanMyIPhone
//

//
//  文件职责：负责 AppState 状态的持久化与恢复。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 保存最近的媒体分类结果、是否部分完成及可用于验证缓存的新旧相册修订。
nonisolated struct MediaStateSnapshot: Codable, Sendable {
    let result: MediaClassificationResult
    let isPartial: Bool
    let libraryRevision: MediaLibraryRevision?

    /// 保存分类结果及其完整性标记；未提供修订号时，后续无法用该值验证相册版本。
    init(
        result: MediaClassificationResult,
        isPartial: Bool,
        libraryRevision: MediaLibraryRevision? = nil
    ) {
        self.result = result
        self.isPartial = isPartial
        self.libraryRevision = libraryRevision
    }
}

/// A compact, deterministic description of the PhotoKit inventory used by an analysis.
/// It lets cold launches validate cached results without loading every thumbnail again.
nonisolated struct MediaLibraryRevision: Codable, Equatable, Sendable {
    let assetCount: Int
    let fingerprint: UInt64
}

/// Stores verified PhotoKit resource sizes. Modification dates invalidate stale entries.
nonisolated struct MediaSizeIndexSnapshot: Codable, Sendable {
    let entries: [String: MediaSizeIndexEntry]
}

/// 保存某资源的已验证大小及对应修改时间，供后续判断缓存是否仍适用。
nonisolated struct MediaSizeIndexEntry: Codable, Sendable {
    let modificationDate: Date? 
    let byteCount: Int64
}

/// Hashes are tied to both the source metadata and the dHash pipeline version.
/// This cache never establishes a deletion decision; Vision still verifies pairs.
nonisolated struct MediaHashCacheSnapshot: Codable, Sendable {
    static let currentVersion = 1
    let version: Int
    let entries: [String: Entry]

    /// 一条感知哈希及其源资源元数据键；源文件变化后键不再匹配。
    nonisolated struct Entry: Codable, Sendable {
        let cacheKey: FeatureCacheKey
        let hash: UInt64
    }

    var compatibleEntries: [String: Entry] {
        version == Self.currentVersion ? entries : [:]
    }
}

/// 保存目录授权书签、展示名、相对文件记录及跳过数量，并携带架构版本。
nonisolated struct FileStateSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 3

    let schemaVersion: Int?
    let directoryBookmark: Data
    let selectedDirectoryName: String
    let files: [PersistedScannedFile]
    let skippedFileCount: Int

    /// 将扫描结果转换为相对路径记录，并写入当前快照版本和目录授权书签。
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
    /// 分批检查取消并生成持久化记录；扫描已被替代时返回 nil，避免继续构造旧快照。
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

    /// 接收已分批转换完成的记录，供可取消的 `prepare` 路径构造快照。
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

    /// 兼容旧版快照使用的完整字段名，仅用于读取历史数据。
    private enum LegacyCodingKeys: String, CodingKey {
        case name
        case relativePathComponents
        case category
        case byteCount
        case hasKnownByteCount
        case creationDate
        case modificationDate
    }

    /// 从扫描结果提取可持久化的相对路径及元数据，不保存临时的提供方绝对 URL。
    init(_ file: ScannedFile) {
        name = file.name
        relativePathComponents = file.relativePathComponents
        category = file.category
        byteCount = file.byteCount
        hasKnownByteCount = file.hasKnownByteCount
        creationDate = file.creationDate
        modificationDate = file.modificationDate
    }

    /// 优先读取紧凑字段名；旧格式仍使用原字段名解码，以兼容已有快照。
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

/// 串行读写应用支持目录中的 JSON 状态；缓存缺失或损坏时返回 nil。
actor AppStateStore {
    static let shared = AppStateStore()

    /// 各快照在应用私有状态目录中的文件名，避免不同缓存互相覆盖。
    private enum SnapshotName: String {
        case media = "media-state.json"
        case mediaSizes = "media-size-index.json"
        case mediaHashes = "media-hash-cache.json"
        case files = "file-state.json"
        case fileDashboard = "file-dashboard.json"
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directoryURL: URL

    /// 选择应用支持目录作为持久化根目录，系统未提供时回退到临时目录。
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

    /// 读取媒体分类快照；文件缺失或无法解码时返回 nil。
    func loadMediaState() -> MediaStateSnapshot? {
        load(MediaStateSnapshot.self, name: .media)
    }

    /// 保存媒体分类快照；传入 nil 时移除对应缓存。
    func saveMediaState(_ snapshot: MediaStateSnapshot?) {
        save(snapshot, name: .media)
    }

    /// 读取资源精确大小索引，供调用方按修改时间验证。
    func loadMediaSizeIndex() -> MediaSizeIndexSnapshot? {
        load(MediaSizeIndexSnapshot.self, name: .mediaSizes)
    }

    /// 保存资源大小索引；传入 nil 时移除对应缓存。
    func saveMediaSizeIndex(_ snapshot: MediaSizeIndexSnapshot?) {
        save(snapshot, name: .mediaSizes)
    }

    /// 读取感知哈希缓存；版本兼容性由快照模型判断。
    func loadMediaHashCache() -> MediaHashCacheSnapshot? {
        load(MediaHashCacheSnapshot.self, name: .mediaHashes)
    }

    /// 保存感知哈希缓存，以便后续相册分析复用。
    func saveMediaHashCache(_ snapshot: MediaHashCacheSnapshot) {
        save(snapshot, name: .mediaHashes)
    }

    /// 读取完整文件扫描快照，并记录聚合加载耗时。
    func loadFileState() -> FileStateSnapshot? {
        let interval = StoragePerformance.begin("Storage Snapshot Load")
        defer { StoragePerformance.end("Storage Snapshot Load", id: interval) }
        return load(FileStateSnapshot.self, name: .files)
    }

    /// 保存或移除完整文件扫描快照，并记录聚合写入耗时。
    func saveFileState(_ snapshot: FileStateSnapshot?) {
        let interval = StoragePerformance.begin("Storage Snapshot Save")
        defer { StoragePerformance.end("Storage Snapshot Save", id: interval) }
        save(snapshot, name: .files)
    }

    /// 读取小型概览快照，使界面无需先解码完整文件索引。
    func loadStorageDashboard() -> StorageDashboardSnapshot? {
        let interval = StoragePerformance.begin("Storage Dashboard Load")
        defer { StoragePerformance.end("Storage Dashboard Load", id: interval) }
        return load(StorageDashboardSnapshot.self, name: .fileDashboard)
    }

    /// 保存或移除存储概览快照。
    func saveStorageDashboard(_ snapshot: StorageDashboardSnapshot?) {
        save(snapshot, name: .fileDashboard)
    }

    /// 从指定文件读取并解码快照；读取或解码失败统一返回 nil。
    private func load<T: Decodable>(_ type: T.Type, name: SnapshotName) -> T? {
        let url = directoryURL.appendingPathComponent(name.rawValue)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    /// 原子写入非空快照；空值移除缓存。持久化失败被忽略，不阻断业务操作。
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
