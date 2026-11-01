//
//  文件快照编码
//
//  按持久化格式逐项编码扫描记录，避免额外构造一份完整记录数组。
//  读取路径支持系统按需映射；编码期间定期检查取消，不改变快照格式。
//

import Foundation

/// Encodes schema v3 without first materializing a second array of persisted file records.
/// The original decoder, bookmark bytes and atomic write path remain unchanged.
/// 将扫描文件直接写入快照的无键数组，避免构造第二个完整持久化记录数组。
nonisolated struct FileSnapshotEncodingCandidate: Encodable {
    let directoryBookmark: Data
    let selectedDirectoryName: String
    let files: [ScannedFile]
    let skippedFileCount: Int

    /// Candidate read path for the app-owned, atomically replaced snapshot file.
    /// Mapping is advisory; Foundation may fall back to a normal read.
    /// 解码应用自己的快照文件，并在读取前后检查取消；映射只是系统可选的读取优化。
    static func decode(from url: URL) throws -> FileStateSnapshot {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try Task.checkCancellation()
        return try JSONDecoder().decode(FileStateSnapshot.self, from: data)
    }

    /// 与 `FileStateSnapshot` 对应的顶层字段；文件记录使用各自的紧凑编码键。
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, directoryBookmark, selectedDirectoryName, files, skippedFileCount
    }

    /// 按当前版本写入固定字段，逐项转换文件记录并定期检查取消。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(FileStateSnapshot.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(directoryBookmark, forKey: .directoryBookmark)
        try container.encode(selectedDirectoryName, forKey: .selectedDirectoryName)
        try container.encode(skippedFileCount, forKey: .skippedFileCount)
        var records = container.nestedUnkeyedContainer(forKey: .files)
        for (index, file) in files.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            try records.encode(PersistedScannedFile(file))
        }
    }
}
