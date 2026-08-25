//
//  AppStateStore.swift
//  CleanMyIPhone
//

import Foundation

nonisolated struct MediaStateSnapshot: Codable, Sendable {
    let result: MediaClassificationResult
    let isPartial: Bool
}

nonisolated struct FileStateSnapshot: Codable, Sendable {
    let directoryBookmark: Data
    let selectedDirectoryName: String
    let files: [ScannedFile]
    let skippedFileCount: Int
}

actor AppStateStore {
    static let shared = AppStateStore()

    private enum SnapshotName: String {
        case media = "media-state.json"
        case files = "file-state.json"
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directoryURL: URL

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

    func loadMediaState() -> MediaStateSnapshot? {
        load(MediaStateSnapshot.self, name: .media)
    }

    func saveMediaState(_ snapshot: MediaStateSnapshot?) {
        save(snapshot, name: .media)
    }

    func loadFileState() -> FileStateSnapshot? {
        load(FileStateSnapshot.self, name: .files)
    }

    func saveFileState(_ snapshot: FileStateSnapshot?) {
        save(snapshot, name: .files)
    }

    private func load<T: Decodable>(_ type: T.Type, name: SnapshotName) -> T? {
        let url = directoryURL.appendingPathComponent(name.rawValue)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

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
