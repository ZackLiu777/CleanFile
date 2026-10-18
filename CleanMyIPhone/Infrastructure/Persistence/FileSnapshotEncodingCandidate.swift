import Foundation

/// Encodes schema v3 without first materializing a second array of persisted file records.
/// The original decoder, bookmark bytes and atomic write path remain unchanged.
nonisolated struct FileSnapshotEncodingCandidate: Encodable {
    let directoryBookmark: Data
    let selectedDirectoryName: String
    let files: [ScannedFile]
    let skippedFileCount: Int

    /// Candidate read path for the app-owned, atomically replaced snapshot file.
    /// Mapping is advisory; Foundation may fall back to a normal read.
    static func decode(from url: URL) throws -> FileStateSnapshot {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try Task.checkCancellation()
        return try JSONDecoder().decode(FileStateSnapshot.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, directoryBookmark, selectedDirectoryName, files, skippedFileCount
    }

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
