//
//  文件扫描领域模型
//
//  定义文件元数据、类别、统计累加器、扫描事件及删除状态。
//  文件大小可能未知；结果描述扫描快照，不保证源文件在后续操作时仍可访问。
//

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

/// 文件概览使用的分类；无法识别的类型归入 other。
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
        case .video: AppL10n.string("Videos")
        case .image: AppL10n.string("Images")
        case .audio: AppL10n.string("Audio")
        case .document: AppL10n.string("Documents")
        case .pdf: AppL10n.string("PDFs")
        case .archive: AppL10n.string("Archives")
        case .other: AppL10n.string("Other")
        }
    }

    /// 优先按系统类型标识判断；缺失或不能识别时回退到扩展名。
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

    /// 按不区分大小写的已知扩展名分类，不读取文件内容。
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

/// 一次扫描得到的文件元数据快照；大小未知时须结合 hasKnownByteCount 判断。
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

    /// URL 用于恢复快照中的标识，因此不另行编码派生的 `id`。
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

    /// 以给定的相对路径和元数据构建记录；URL 同时作为当前快照的标识。
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

    /// 从系统资源值构建记录；缺少名称时使用 URL 末尾，缺少大小时标记未知。
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

    /// 解码文件记录并通过常规初始化恢复 URL 标识。
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

    /// 编码文件 URL、相对路径及元数据，保留大小是否已知的信息。
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

/// 集中定义文件列表的展示排序规则。
nonisolated enum FileDisplayOrder {
    /// 已知大小排在未知大小之前，随后按大小降序及本地化名称排序。
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

/// 从标准化文件 URL 中提取相对于选定根目录的安全路径组件。
enum RelativePathComponents: Sendable {
    /// Produces the file's hierarchy below the user-selected root without guessing.
    /// 从根 URL 构造路径组件并委托校验；不属于根目录或与根相同的 URL 返回 nil。
    nonisolated static func make(fileURL: URL, relativeTo rootURL: URL) -> [String]? {
        make(
            fileURL: fileURL,
            rootComponents: rootURL.standardizedFileURL.pathComponents
        )
    }

    /// Reuses the selected root's components across a large directory walk.
    /// 复用已计算的根组件，验证标准化后的文件路径属于根目录且相对组件有效。
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

/// 单个文件类别的数量、已知字节、未知大小数量和已知字节占比。
nonisolated struct StorageCategorySummary: Identifiable, Codable, Hashable, Sendable {
    let category: FileCategory
    let fileCount: Int
    let byteCount: Int64
    let unknownByteCount: Int
    let percentage: Double

    var id: FileCategory { category }
}

/// 文件扫描的整体数量、已知大小和分类汇总；未知大小单独计数。
nonisolated struct StorageSummary: Codable, Hashable, Sendable {
    let fileCount: Int
    let totalBytes: Int64
    let unknownByteCountFileCount: Int
    let categories: [StorageCategorySummary]

    /// 逐项累积文件记录并生成统计结果，不访问源文件。
    nonisolated init(files: [ScannedFile]) {
        var accumulator = StorageSummaryAccumulator()
        for file in files {
            accumulator.append(file)
        }
        self = accumulator.makeSummary()
    }

    /// 使用已计算的计数和分类结果构造汇总；调用方负责保证各项统计一致。
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
/// 随扫描增量汇总文件分类，避免完成后再多次遍历所有记录。
nonisolated struct StorageSummaryAccumulator: Sendable {
    /// 某一分类的增量统计；未知大小单独计数，不加入字节总量。
    private struct CategoryValues: Sendable {
        var fileCount = 0
        var byteCount: Int64 = 0
        var unknownByteCount = 0
    }

    private var fileCount = 0
    private var totalBytes: Int64 = 0
    private var unknownByteCountFileCount = 0
    private var grouped: [FileCategory: CategoryValues] = [:]

    /// 计入文件及其分类；只有大小已知时才加入字节总量。
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

    /// 为所有分类生成汇总，占比以已知总字节为分母，零总量时为零。
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
/// 以固定容量的最小堆保存最大的已知大小文件，避免对全部文件排序。
nonisolated struct LargestFilesAccumulator: Sendable {
    private let limit: Int
    private var heap: [ScannedFile] = []

    /// 设置保留数量；负数按零处理。
    init(limit: Int) {
        self.limit = max(0, limit)
        heap.reserveCapacity(self.limit)
    }

    /// 忽略大小未知的文件；堆满时仅用更大的候选替换堆顶。
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

    /// 按大小降序、名称升序输出当前候选，不改变堆。
    func sortedDescending() -> [ScannedFile] {
        heap.sorted { lhs, rhs in
            if lhs.byteCount != rhs.byteCount {
                return lhs.byteCount > rhs.byteCount
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// 新节点插入后向上恢复最小堆顺序。
    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard isLarger(heap[parent], than: heap[child]) else { return }
            heap.swapAt(parent, child)
            child = parent
        }
    }

    /// 替换堆顶后向下恢复最小堆顺序。
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

    /// 按大小及名称判断候选顺序，使堆内大小相同时仍有确定的比较规则。
    private func isLarger(_ lhs: ScannedFile, than rhs: ScannedFile) -> Bool {
        if lhs.byteCount != rhs.byteCount {
            return lhs.byteCount > rhs.byteCount
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
    }
}

/// 扫描阶段已发现的文件数与字节数。
struct ScanProgress: Equatable, Sendable {
    let scannedFileCount: Int
    let scannedByteCount: Int64
}

/// 完整或部分扫描得到的文件、失败记录、概览、目录树与大文件候选。
struct FileScanResult: Sendable {
    let files: [ScannedFile]
    let failures: [FileScanFailure]
    let summary: StorageSummary
    let fileTree: FileNode
    let largestFiles: [ScannedFile]
}

/// 单个扫描项目无法处理时记录的名称与原因，允许其余项目继续。
struct FileScanFailure: Hashable, Sendable {
    let fileName: String
    let reason: FileScanFailureReason
}

/// 记录项目不可访问或无法生成相对路径等局部失败原因。
enum FileScanFailureReason: String, Error, Hashable, Sendable {
    case inaccessible
    case relativePathUnavailable
}

/// 扫描流发送的进度或最终结果事件。
enum FileScanEvent: Sendable {
    case progress(ScanProgress)
    case completed(FileScanResult)
}

/// 扫描无法继续时使用的取消、来源、枚举和授权错误。
enum FileScanError: LocalizedError, Equatable, Sendable {
    case cancelled
    case notDirectory
    case unableToEnumerate
    case securityScopeUnavailable
    case selectionFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: AppL10n.string("The scan was cancelled.")
        case .notDirectory: AppL10n.string("Please choose a folder.")
        case .unableToEnumerate: AppL10n.string("The selected folder could not be read.")
        case .securityScopeUnavailable: AppL10n.string("Access to the selected folder could not be obtained.")
        case .selectionFailed: AppL10n.string("The selected folder could not be opened.")
        }
    }
}

/// 界面消费的扫描状态，包括部分成功、取消和失败。
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

/// 记录成功删除的 URL 集合和失败文件数，供调用方更新状态。
struct FileDeletionResult: Equatable, Sendable {
    let deletedURLs: Set<URL>
    let failedFileCount: Int
}

/// 删除操作的互斥状态，单独表示部分成功。
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

/// 区分未选择目标、授权不可用、越界选择及删除失败。
enum FileDeletionError: LocalizedError, Equatable, Sendable {
    case noItemsSelected
    case folderAccessUnavailable
    case invalidSelection
    case deletionFailed

    var errorDescription: String? {
        switch self {
        case .noItemsSelected: AppL10n.string("Select at least one file to delete.")
        case .folderAccessUnavailable: AppL10n.string("Access to the selected folder is no longer available.")
        case .invalidSelection: AppL10n.string("One or more selected files are outside the analyzed folder.")
        case .deletionFailed: AppL10n.string("The selected files could not be deleted.")
        }
    }
}
