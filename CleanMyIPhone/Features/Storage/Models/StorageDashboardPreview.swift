import Foundation

/// A URL-free example, never inserted into the scanner, bookmarks, or persisted user index.
struct StorageDashboardPreview {
    let summary: StorageSummary
    let fileTree: FileNode
    static let example = make()

    static func make() -> Self {
        let examples: [(category: FileCategory, count: Int, bytes: Int64, fileExtension: String)] = [
            (.video, 12, 6_800_000_000, "mov"),
            (.image, 84, 1_200_000_000, "heic"),
            (.audio, 24, 420_000_000, "m4a"),
            (.document, 36, 180_000_000, "txt"),
            (.pdf, 16, 120_000_000, "pdf"),
            (.archive, 8, 800_000_000, "zip"),
            (.other, 10, 40_000_000, "dat")
        ]
        let totalBytes = examples.reduce(Int64.zero) { $0 + $1.bytes }
        let categories = examples.map {
            StorageCategorySummary(
                category: $0.category,
                fileCount: $0.count,
                byteCount: $0.bytes,
                unknownByteCount: 0,
                percentage: Double($0.bytes) / Double(totalBytes)
            )
        }
        let folders = examples.map { example in
            let files = (0..<example.count).map { index in
                let name = String(format: "%03d", index + 1) + "." + example.fileExtension
                let bytes = example.bytes / Int64(example.count)
                    + (index == example.count - 1 ? example.bytes % Int64(example.count) : 0)
                return FileNode(
                    id: "preview/\(example.category.rawValue)/\(index)",
                    name: name,
                    byteCount: bytes,
                    children: [],
                    category: example.category,
                    isDirectory: false
                )
            }
            let groups = stride(from: 0, to: files.count, by: 4).map { start in
                let id = "preview/\(example.category.rawValue)/group-\(start / 4)"
                let children = Array(files[start..<min(start + 4, files.count)])
                // Uneven branches produce the same open-ended radial silhouette as a real scan.
                var branch = children
                let depth = (start / 4) % 5
                for level in 0..<depth {
                    branch = [directory(
                        id: id + "/level-\(level)",
                        name: String(format: "%02d", level + 1),
                        children: branch
                    )]
                }
                return directory(
                    id: id,
                    name: String(format: "%02d", start / 4 + 1),
                    children: branch
                )
            }
            return directory(
                id: "preview/" + example.category.rawValue,
                name: example.category.displayName,
                children: groups
            )
        }
        return Self(
            summary: StorageSummary(
                fileCount: examples.reduce(0) { $0 + $1.count },
                totalBytes: totalBytes,
                unknownByteCountFileCount: 0,
                categories: categories
            ),
            fileTree: directory(
                id: "preview",
                name: AppL10n.string("storage.preview.folder"),
                children: folders.sorted { $0.byteCount > $1.byteCount }
            )
        )
    }

    private static func directory(id: String, name: String, children: [FileNode]) -> FileNode {
        FileNode(
            id: id,
            name: name,
            byteCount: children.reduce(Int64.zero) { $0 + $1.byteCount },
            children: children,
            category: children.max(by: { $0.byteCount < $1.byteCount })?.category,
            isDirectory: true
        )
    }
}
