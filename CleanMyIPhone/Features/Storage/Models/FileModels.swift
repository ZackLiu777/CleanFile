//
//  FileModels.swift
//  CleanMyIPhone
//

//
//  文件职责：定义 File 领域使用的数据模型与状态语义。
//  所属模块：CleanMyIPhone。
//

import Foundation
import UniformTypeIdentifiers

/// 定义 `FileCategory` 使用的有限状态或选项集合。
nonisolated enum FileCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case video
    case image
    case audio
    case document
    case pdf
    case archive
    case other

    var displayName: String {
        switch self {
        case .video: String(localized: "Videos")
        case .image: String(localized: "Images")
        case .audio: String(localized: "Audio")
        case .document: String(localized: "Documents")
        case .pdf: String(localized: "PDFs")
        case .archive: String(localized: "Archives")
        case .other: String(localized: "Other")
        }
    }

    /// 解析 `classify` 对应的业务语义，并返回稳定的分类或映射结果。
    nonisolated static func classify(typeIdentifier: String?, fileExtension: String) -> FileCategory {
        if let typeIdentifier, let type = UTType(typeIdentifier) {
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            }
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .audio) {
                return .audio
            }
            if type.conforms(to: .pdf) {
                return .pdf
            }
            if type.conforms(to: .archive) {
                return .archive
            }
            if type.conforms(to: .text) || type.conforms(to: .sourceCode) {
                return .document
            }
        }

        return classify(fileExtension: fileExtension)
    }

    /// 解析 `classify` 对应的业务语义，并返回稳定的分类或映射结果。
    nonisolated static func classify(fileExtension: String) -> FileCategory {
        switch fileExtension.lowercased() {
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": .video
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp": .image
        case "mp3", "m4a", "wav", "flac", "aac", "ogg": .audio
        case "pdf": .pdf
        case "zip", "tar", "gz", "gzip", "rar", "7z": .archive
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "txt", "md", "csv", "html", "json": .document
        default: .other
        }
    }
}

/// 定义 `ScannedFile` 的值语义数据与相关行为。
nonisolated struct ScannedFile: Identifiable, Codable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let relativePathComponents: [String]
    let category: FileCategory
    let byteCount: Int64
    let hasKnownByteCount: Bool
    let creationDate: Date?
    let modificationDate: Date?

    private enum CodingKeys: String, CodingKey {
        case url
        case name
        case relativePathComponents
        case category
        case byteCount
        case hasKnownByteCount
        case creationDate
        case modificationDate
    }

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    nonisolated init(
        url: URL,
        name: String,
        relativePathComponents: [String],
        category: FileCategory,
        byteCount: Int64,
        hasKnownByteCount: Bool = true,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.id = url
        self.url = url
        self.name = name
        self.relativePathComponents = relativePathComponents
        self.category = category
        self.byteCount = byteCount
        self.hasKnownByteCount = hasKnownByteCount
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    nonisolated init(
        url: URL,
        resourceValues: URLResourceValues,
        relativePathComponents: [String]
    ) {
        self.init(
            url: url,
            name: resourceValues.name ?? url.lastPathComponent,
            relativePathComponents: relativePathComponents,
            category: FileCategory.classify(
                typeIdentifier: resourceValues.typeIdentifier,
                fileExtension: url.pathExtension
            ),
            byteCount: Int64(resourceValues.fileSize ?? 0),
            hasKnownByteCount: resourceValues.fileSize != nil,
            creationDate: resourceValues.creationDate,
            modificationDate: resourceValues.contentModificationDate
        )
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let url = try container.decode(URL.self, forKey: .url)
        self.init(
            url: url,
            name: try container.decode(String.self, forKey: .name),
            relativePathComponents: try container.decode([String].self, forKey: .relativePathComponents),
            category: try container.decode(FileCategory.self, forKey: .category),
            byteCount: try container.decode(Int64.self, forKey: .byteCount),
            hasKnownByteCount: try container.decode(Bool.self, forKey: .hasKnownByteCount),
            creationDate: try container.decodeIfPresent(Date.self, forKey: .creationDate),
            modificationDate: try container.decodeIfPresent(Date.self, forKey: .modificationDate)
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(relativePathComponents, forKey: .relativePathComponents)
        try container.encode(category, forKey: .category)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encode(hasKnownByteCount, forKey: .hasKnownByteCount)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(modificationDate, forKey: .modificationDate)
    }
}

/// 定义 `FileDisplayOrder` 使用的有限状态或选项集合。
nonisolated enum FileDisplayOrder {
    /// 封装 `bySizeDescending` 对应的局部行为，供当前类型在统一入口下复用。
    static func bySizeDescending(_ files: [ScannedFile]) -> [ScannedFile] {
        files.sorted { lhs, rhs in
            if lhs.hasKnownByteCount != rhs.hasKnownByteCount {
                return lhs.hasKnownByteCount
            }
            if lhs.byteCount != rhs.byteCount {
                return lhs.byteCount > rhs.byteCount
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// 定义 `RelativePathComponents` 使用的有限状态或选项集合。
enum RelativePathComponents: Sendable {
    /// Produces the file's hierarchy below the user-selected root without guessing.
    nonisolated static func make(fileURL: URL, relativeTo rootURL: URL) -> [String]? {
        make(
            fileURL: fileURL,
            rootComponents: rootURL.standardizedFileURL.pathComponents
        )
    }

    /// Reuses the selected root's components across a large directory walk.
    nonisolated static func make(
        fileURL: URL,
        rootComponents: [String]
    ) -> [String]? {
        // Normalize lexical "." and ".." segments before checking ancestry.
        // An escaping path then loses the root prefix, while an in-root "./"
        // segment remains a valid relative path.
        let fileComponents = fileURL.standardizedFileURL.pathComponents

        guard fileComponents.starts(with: rootComponents) else {
            return nil
        }

        let relativeComponents = fileComponents.dropFirst(rootComponents.count)
        guard !relativeComponents.isEmpty else {
            return nil
        }

        let components = relativeComponents.map { String($0) }
        guard components.allSatisfy({ !$0.isEmpty && $0 != "/" && $0 != "." && $0 != ".." }) else {
            return nil
        }

        return components
    }
}

/// 定义 `StorageCategorySummary` 的值语义数据与相关行为。
nonisolated struct StorageCategorySummary: Identifiable, Codable, Hashable, Sendable {
    let category: FileCategory
    let fileCount: Int
    let byteCount: Int64
    let unknownByteCount: Int
    let percentage: Double

    var id: FileCategory { category }
}

/// 定义 `StorageSummary` 的值语义数据与相关行为。
nonisolated struct StorageSummary: Codable, Hashable, Sendable {
    let fileCount: Int
    let totalBytes: Int64
    let unknownByteCountFileCount: Int
    let categories: [StorageCategorySummary]

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    nonisolated init(files: [ScannedFile]) {
        var accumulator = StorageSummaryAccumulator()
        for file in files {
            accumulator.append(file)
        }
        self = accumulator.makeSummary()
    }

    nonisolated init(
        fileCount: Int,
        totalBytes: Int64,
        unknownByteCountFileCount: Int,
        categories: [StorageCategorySummary]
    ) {
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.unknownByteCountFileCount = unknownByteCountFileCount
        self.categories = categories
    }

    var nonEmptyCategories: [StorageCategorySummary] {
        categories.filter { $0.fileCount > 0 }
    }
}

/// Builds the dashboard summary during enumeration so completion does not
/// traverse every scanned file several more times.
nonisolated struct StorageSummaryAccumulator: Sendable {
    private struct CategoryValues: Sendable {
        var fileCount = 0
        var byteCount: Int64 = 0
        var unknownByteCount = 0
    }

    private var fileCount = 0
    private var totalBytes: Int64 = 0
    private var unknownByteCountFileCount = 0
    private var grouped: [FileCategory: CategoryValues] = [:]

    mutating func append(_ file: ScannedFile) {
        fileCount += 1
        var values = grouped[file.category, default: CategoryValues()]
        values.fileCount += 1

        if file.hasKnownByteCount {
            totalBytes += file.byteCount
            values.byteCount += file.byteCount
        } else {
            unknownByteCountFileCount += 1
            values.unknownByteCount += 1
        }

        grouped[file.category] = values
    }

    func makeSummary() -> StorageSummary {
        let categories = FileCategory.allCases.map { category in
            let values = grouped[category, default: CategoryValues()]
            let percentage = totalBytes == 0 ? 0 : Double(values.byteCount) / Double(totalBytes)
            return StorageCategorySummary(
                category: category,
                fileCount: values.fileCount,
                byteCount: values.byteCount,
                unknownByteCount: values.unknownByteCount,
                percentage: percentage
            )
        }

        return StorageSummary(
            fileCount: fileCount,
            totalBytes: totalBytes,
            unknownByteCountFileCount: unknownByteCountFileCount,
            categories: categories
        )
    }
}

/// Keeps only the largest files in a fixed-size min-heap. For the dashboard's
/// ten entries this changes the scan-end full sort into O(n log 10) work.
nonisolated struct LargestFilesAccumulator: Sendable {
    private let limit: Int
    private var heap: [ScannedFile] = []

    init(limit: Int) {
        self.limit = max(0, limit)
        heap.reserveCapacity(self.limit)
    }

    mutating func append(_ file: ScannedFile) {
        guard limit > 0, file.hasKnownByteCount else { return }

        if heap.count < limit {
            heap.append(file)
            siftUp(from: heap.count - 1)
            return
        }

        guard isLarger(file, than: heap[0]) else { return }
        heap[0] = file
        siftDown(from: 0)
    }

    func sortedDescending() -> [ScannedFile] {
        heap.sorted { lhs, rhs in
            if lhs.byteCount != rhs.byteCount {
                return lhs.byteCount > rhs.byteCount
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard isLarger(heap[parent], than: heap[child]) else { return }
            heap.swapAt(parent, child)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            var smallest = left
            if right < heap.count, isLarger(heap[left], than: heap[right]) {
                smallest = right
            }
            guard isLarger(heap[parent], than: heap[smallest]) else { return }
            heap.swapAt(parent, smallest)
            parent = smallest
        }
    }

    private func isLarger(_ lhs: ScannedFile, than rhs: ScannedFile) -> Bool {
        if lhs.byteCount != rhs.byteCount {
            return lhs.byteCount > rhs.byteCount
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
    }
}

/// 定义 `ScanProgress` 的值语义数据与相关行为。
struct ScanProgress: Equatable, Sendable {
    let scannedFileCount: Int
    let scannedByteCount: Int64
}

/// 定义 `FileScanResult` 的值语义数据与相关行为。
struct FileScanResult: Sendable {
    let files: [ScannedFile]
    let failures: [FileScanFailure]
    let summary: StorageSummary
    let fileTree: FileNode
    let largestFiles: [ScannedFile]
}

/// 定义 `FileScanFailure` 的值语义数据与相关行为。
struct FileScanFailure: Hashable, Sendable {
    let fileName: String
    let reason: FileScanFailureReason
}

/// 定义 `FileScanFailureReason` 使用的有限状态或选项集合。
enum FileScanFailureReason: String, Error, Hashable, Sendable {
    case inaccessible
    case relativePathUnavailable
}

/// 定义 `FileScanEvent` 使用的有限状态或选项集合。
enum FileScanEvent: Sendable {
    case progress(ScanProgress)
    case completed(FileScanResult)
}

/// 定义 `FileScanError` 使用的有限状态或选项集合。
enum FileScanError: LocalizedError, Equatable, Sendable {
    case cancelled
    case notDirectory
    case unableToEnumerate
    case securityScopeUnavailable
    case selectionFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: String(localized: "The scan was cancelled.")
        case .notDirectory: String(localized: "Please choose a folder.")
        case .unableToEnumerate: String(localized: "The selected folder could not be read.")
        case .securityScopeUnavailable: String(localized: "Access to the selected folder could not be obtained.")
        case .selectionFailed: String(localized: "The selected folder could not be opened.")
        }
    }
}

/// 定义 `ScanState` 使用的有限状态或选项集合。
enum ScanState: Equatable, Sendable {
    case idle
    case scanning(ScanProgress)
    case success(StorageSummary)
    case empty
    case partialFailure(StorageSummary, skippedFileCount: Int)
    case cancelled
    case failure(FileScanError)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

/// 定义 `FileDeletionResult` 的值语义数据与相关行为。
struct FileDeletionResult: Equatable, Sendable {
    let deletedURLs: Set<URL>
    let failedFileCount: Int
}

/// 定义 `FileDeletionState` 使用的有限状态或选项集合。
enum FileDeletionState: Equatable, Sendable {
    case idle
    case deleting(itemCount: Int)
    case success(deletedCount: Int)
    case partialFailure(deletedCount: Int, failedCount: Int)
    case failure(FileDeletionError)

    var isDeleting: Bool {
        if case .deleting = self { return true }
        return false
    }
}

/// 定义 `FileDeletionError` 使用的有限状态或选项集合。
enum FileDeletionError: LocalizedError, Equatable, Sendable {
    case noItemsSelected
    case folderAccessUnavailable
    case invalidSelection
    case deletionFailed

    var errorDescription: String? {
        switch self {
        case .noItemsSelected: String(localized: "Select at least one file to delete.")
        case .folderAccessUnavailable: String(localized: "Access to the selected folder is no longer available.")
        case .invalidSelection: String(localized: "One or more selected files are outside the analyzed folder.")
        case .deletionFailed: String(localized: "The selected files could not be deleted.")
        }
    }
}
