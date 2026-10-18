import Foundation

/// Stable selection algorithms; original implementations are retained for regression comparisons.
nonisolated enum StorageSelectionAlgorithms {
    static func originalLargest(_ files: [ScannedFile]) -> [ScannedFile] {
        Array(files.sorted { $0.byteCount > $1.byteCount }.prefix(10))
    }

    static func largest(_ files: [ScannedFile]) -> [ScannedFile] {
        guard files.count > 32 else { return originalLargest(files) }
        // Move only indexes: shifting complete file models repeatedly retains/releases URLs and strings.
        var indexes: [Int] = []
        indexes.reserveCapacity(10)
        for index in files.indices {
            let size = files[index].byteCount
            if indexes.count == 10, size <= files[indexes[9]].byteCount { continue }
            let insertion = indexes.firstIndex { size > files[$0].byteCount } ?? indexes.count
            indexes.insert(index, at: insertion)
            if indexes.count > 10 { indexes.removeLast() }
        }
        return indexes.map { files[$0] }
    }

    static func originalSources(_ sources: [URL]) -> [URL] {
        sources.reduce(into: [URL]()) { result, source in
            let normalized = source.standardizedFileURL
            if !result.contains(where: { $0.standardizedFileURL == normalized }) {
                result.append(source)
            }
        }
    }

    static func sources(_ sources: [URL]) -> [URL] {
        guard sources.count > 1 else { return sources }
        var seen: Set<URL> = []
        return sources.filter { seen.insert($0.standardizedFileURL).inserted }
    }
}
