//
//  文件模型极端输入
//
//  覆盖扩展名、深层 Unicode 路径、目录树和最大文件累加边界。
//  重点验证未知大小、非法路径及空集合不会破坏统计或排序。
//  系统类型标识优先于误导性的扩展名，根目录外路径不得成为相对路径。
//  测试使用内存构造的元数据及示例 URL，不需要读取用户文件。
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CleanMyIPhone

/// 以边界输入验证文件分类、路径和统计模型的稳定行为。
@Suite("File model edge cases")
struct ExtremeFileModelTests {
    /// 逐一核对支持的扩展名及大小写变体对应的文件类别。
    @Test("Every supported extension maps to the intended category")
    func supportedExtensionsRemainExhaustive() {
        let expected: [(String, FileCategory)] = [
            ("mp4", .video), ("MOV", .video), ("m4v", .video), ("avi", .video),
            ("mkv", .video), ("webm", .video),
            ("jpg", .image), ("jpeg", .image), ("PNG", .image), ("heic", .image),
            ("heif", .image), ("gif", .image), ("tiff", .image), ("webp", .image),
            ("mp3", .audio), ("m4a", .audio), ("wav", .audio), ("flac", .audio),
            ("aac", .audio), ("ogg", .audio),
            ("pdf", .pdf), ("zip", .archive), ("tar", .archive), ("gz", .archive),
            ("gzip", .archive), ("rar", .archive), ("7z", .archive),
            ("doc", .document), ("docx", .document), ("xls", .document),
            ("xlsx", .document), ("ppt", .document), ("pptx", .document),
            ("rtf", .document), ("txt", .document), ("md", .document),
            ("csv", .document), ("html", .document), ("json", .document)
        ]

        for (fileExtension, category) in expected {
            #expect(FileCategory.classify(fileExtension: fileExtension) == category)
        }
    }

    /// 空字符串、带点或空白以及未知 Unicode 输入都不能误判为已知扩展名。
    @Test("Unrecognized extension input is safe for whitespace, dot files, and Unicode")
    func malformedExtensionsRemainOther() {
        for value in ["", ".jpg", " jpg ", "文件.未知", "nil", "MP4.tmp"] {
            #expect(FileCategory.classify(fileExtension: value) == .other)
        }
    }

    /// 扩展名与类型标识冲突时，以系统类型标识作为分类依据。
    @Test("Uniform type identifiers override every misleading extension")
    func uniformTypeIdentifierAlwaysWins() {
        let cases: [(String, String, FileCategory)] = [
            (UTType.movie.identifier, "txt", .video),
            (UTType.image.identifier, "zip", .image),
            (UTType.audio.identifier, "pdf", .audio),
            (UTType.pdf.identifier, "jpg", .pdf),
            (UTType.archive.identifier, "mp4", .archive),
            (UTType.sourceCode.identifier, "png", .document)
        ]

        for (identifier, fileExtension, category) in cases {
            #expect(FileCategory.classify(typeIdentifier: identifier, fileExtension: fileExtension) == category)
        }
    }

    /// 验证深层中文目录与文件名被完整保留为相对路径组件。
    @Test("Relative path accepts a deeply nested Unicode file")
    func relativePathHandlesDeepUnicodeHierarchy() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let file = root.appending(path: "一/二/三/四/最终 文件.mov")

        #expect(RelativePathComponents.make(fileURL: file, relativeTo: root) == [
            "一", "二", "三", "四", "最终 文件.mov"
        ])
    }

    /// 覆盖标准化路径中的越界情形，防止把根目录外的项目当作子项。
    @Test("Relative path rejects traversal-like components")
    func relativePathRejectsTraversalComponents() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let rootComponents = root.pathComponents

        #expect(RelativePathComponents.make(
            fileURL: root.appending(path: "../outside.txt"),
            rootComponents: rootComponents
        ) == nil)
        #expect(RelativePathComponents.make(
            fileURL: root.appending(path: "folder/../../outside.txt"),
            rootComponents: rootComponents
        ) == nil)
        #expect(RelativePathComponents.make(
            fileURL: root.appending(path: "./file.txt"),
            rootComponents: rootComponents
        ) == ["file.txt"])
        #expect(RelativePathComponents.make(
            fileURL: root.appending(path: "folder/../inside.txt"),
            rootComponents: rootComponents
        ) == ["inside.txt"])
    }

    /// 验证未知大小不会进入树节点的字节汇总。
    @Test("Unknown byte counts never contribute to the file tree")
    func unknownTreeBytesAreExcluded() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let file = ScannedFile(
            url: root.appending(path: "cloud/item.bin"),
            name: "item.bin",
            relativePathComponents: ["cloud", "item.bin"],
            category: .other,
            byteCount: 9_999,
            hasKnownByteCount: false
        )

        let tree = FileTreeBuilder.build(rootURL: root, files: [file])

        #expect(tree.byteCount == 0)
        #expect(tree.children.first?.byteCount == 0)
        #expect(tree.children.first?.children.first?.byteCount == 0)
    }

    /// 空输入仍产生目录根节点，且其最大子层级为零。
    @Test("Empty tree uses a safe selected-folder name")
    func emptyTreeHasStableRoot() {
        let root = URL(fileURLWithPath: "/")
        let tree = FileTreeBuilder.build(rootURL: root, files: [])

        #expect(tree.id == ".")
        #expect(tree.isDirectory)
        #expect(tree.children.isEmpty)
        #expect(FileTreeDiagnostics.maximumDepth(of: tree) == 0)
    }

    /// 混合类别时，根节点的主类别跟随字节数最大的子节点。
    @Test("Tree dominant category follows the largest child branch")
    func treeDominantCategoryUsesLargestBranch() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let files = [
            ScannedFile(url: root.appending(path: "small.pdf"), name: "small.pdf", relativePathComponents: ["small.pdf"], category: .pdf, byteCount: 1),
            ScannedFile(url: root.appending(path: "large.mp4"), name: "large.mp4", relativePathComponents: ["large.mp4"], category: .video, byteCount: 10)
        ]

        #expect(FileTreeBuilder.build(rootURL: root, files: files).category == .video)
    }

    /// 容量上限为零或负数时，即使追加文件也不返回候选。
    @Test("Largest-files accumulator handles zero and negative limits")
    func largestAccumulatorHandlesDisabledLimits() {
        var zero = LargestFilesAccumulator(limit: 0)
        var negative = LargestFilesAccumulator(limit: -10)
        let file = makeFile(name: "file", bytes: 100)

        zero.append(file)
        negative.append(file)

        #expect(zero.sortedDescending().isEmpty)
        #expect(negative.sortedDescending().isEmpty)
    }

    /// 混合已知和未知大小时，只保留最大的已知文件。
    @Test("Largest-files accumulator excludes unknown sizes and keeps only the top ten")
    func largestAccumulatorKeepsTopKnownFiles() {
        var accumulator = LargestFilesAccumulator(limit: 10)
        for index in 0 ..< 30 {
            accumulator.append(makeFile(
                name: "file-\(index)",
                bytes: Int64(index),
                known: index != 29
            ))
        }

        let result = accumulator.sortedDescending()
        #expect(result.count == 10)
        #expect(result.allSatisfy { $0.hasKnownByteCount })
        #expect(result.map { $0.byteCount } == Array(stride(from: Int64(28), through: Int64(19), by: -1)))
    }

    /// 相同大小的候选按名称形成确定的展示顺序。
    @Test("Largest-files ties use a deterministic localized name order")
    func largestAccumulatorSortsTiesByName() {
        var accumulator = LargestFilesAccumulator(limit: 3)
        accumulator.append(makeFile(name: "zeta", bytes: 42))
        accumulator.append(makeFile(name: "alpha", bytes: 42))
        accumulator.append(makeFile(name: "middle", bytes: 42))

        #expect(accumulator.sortedDescending().map { $0.name } == ["alpha", "middle", "zeta"])
    }

    /// 空汇总保留所有类别槽位，但没有非空类别。
    @Test("Storage summary preserves all category slots for an empty input")
    func emptySummaryPreservesCategoryShape() {
        let summary = StorageSummary(files: [])

        #expect(summary.fileCount == 0)
        #expect(summary.categories.map { $0.category } == FileCategory.allCases)
        #expect(summary.nonEmptyCategories.isEmpty)
    }

    /// 构造不读取磁盘的单层文件记录，可显式模拟大小未知。
    private func makeFile(name: String, bytes: Int64, known: Bool = true) -> ScannedFile {
        ScannedFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            relativePathComponents: [name],
            category: .other,
            byteCount: bytes,
            hasKnownByteCount: known
        )
    }
}
