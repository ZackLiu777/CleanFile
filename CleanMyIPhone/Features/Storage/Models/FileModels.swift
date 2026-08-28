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
        let rootComponents = rootURL.pathComponents
        let fileComponents = fileURL.pathComponents

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
struct StorageCategorySummary: Identifiable, Hashable, Sendable {
    let category: FileCategory
    let fileCount: Int
    let byteCount: Int64
    let unknownByteCount: Int
    let percentage: Double

    var id: FileCategory { category }
}

/// 定义 `StorageSummary` 的值语义数据与相关行为。
struct StorageSummary: Hashable, Sendable {
    let fileCount: Int
    let totalBytes: Int64
    let unknownByteCountFileCount: Int
    let categories: [StorageCategorySummary]

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    nonisolated init(files: [ScannedFile]) {
        let grouped = files.reduce(into: [FileCategory: (fileCount: Int, byteCount: Int64, unknownByteCount: Int)]()) { result, file in
            let current = result[file.category, default: (fileCount: 0, byteCount: 0, unknownByteCount: 0)]
            result[file.category] = (
                fileCount: current.fileCount + 1,
                byteCount: current.byteCount + (file.hasKnownByteCount ? file.byteCount : 0),
                unknownByteCount: current.unknownByteCount + (file.hasKnownByteCount ? 0 : 1)
            )
        }

        let totalBytes = files.reduce(Int64.zero) {
            $0 + ($1.hasKnownByteCount ? $1.byteCount : 0)
        }
        self.fileCount = files.count
        self.totalBytes = totalBytes
        self.unknownByteCountFileCount = files.filter { !$0.hasKnownByteCount }.count
        self.categories = FileCategory.allCases.map { category in
            let values = grouped[category, default: (fileCount: 0, byteCount: 0, unknownByteCount: 0)]
            let percentage = totalBytes == 0 ? 0 : Double(values.byteCount) / Double(totalBytes)
            return StorageCategorySummary(
                category: category,
                fileCount: values.fileCount,
                byteCount: values.byteCount,
                unknownByteCount: values.unknownByteCount,
                percentage: percentage
            )
        }
    }

    var nonEmptyCategories: [StorageCategorySummary] {
        categories.filter { $0.fileCount > 0 }
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
