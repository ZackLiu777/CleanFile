//
//  文件模型行为
//
//  覆盖类型分类、相对路径、大小汇总、目录树和状态模型。
//  同时验证未知大小、空值、同名排序和删除部分成功的表示。
//  分类用例对照类型标识与扩展名；树与汇总用例检查稳定顺序和未知字节。
//  记录均为测试中构造的值和示例路径，不依赖实际文件内容。
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CleanMyIPhone

/// 覆盖文件领域模型的分类、聚合、排序与状态契约。
@Suite("File model behavior")
struct FileModelTests {
    /// 验证扩展名大小写不会改变视频、图片和 PDF 的分类。
    @Test("File extension matching is case insensitive")
    func extensionMatchingIsCaseInsensitive() {
        #expect(FileCategory.classify(fileExtension: "MOV") == .video)
        #expect(FileCategory.classify(fileExtension: "JpEg") == .image)
        #expect(FileCategory.classify(fileExtension: "PDF") == .pdf)
    }

    /// 覆盖常用音频扩展名，防止类型表遗漏已支持的格式。
    @Test("Supported audio extensions are classified")
    func audioExtensionsAreClassified() {
        for fileExtension in ["mp3", "m4a", "wav", "flac", "aac", "ogg"] {
            #expect(FileCategory.classify(fileExtension: fileExtension) == .audio)
        }
    }

    /// 覆盖办公文档和常见文本数据格式的扩展名分类。
    @Test("Supported document extensions are classified")
    func documentExtensionsAreClassified() {
        for fileExtension in ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "csv", "json"] {
            #expect(FileCategory.classify(fileExtension: fileExtension) == .document)
        }
    }

    /// 空扩展名或未知格式统一保留为其他类型。
    @Test("Unknown and empty extensions remain other")
    func unknownExtensionsRemainOther() {
        #expect(FileCategory.classify(fileExtension: "") == .other)
        #expect(FileCategory.classify(fileExtension: "custom-format") == .other)
    }

    /// 类型标识与扩展名冲突时，以系统提供的类型标识为准。
    @Test("Type identifier takes priority over a misleading extension")
    func typeIdentifierTakesPriority() {
        #expect(FileCategory.classify(typeIdentifier: UTType.image.identifier, fileExtension: "txt") == .image)
        #expect(FileCategory.classify(typeIdentifier: UTType.audio.identifier, fileExtension: "pdf") == .audio)
    }

    /// 无法识别类型标识时仍可通过扩展名识别压缩文件。
    @Test("Invalid type identifier falls back to extension")
    func invalidTypeIdentifierFallsBackToExtension() {
        let category = FileCategory.classify(
            typeIdentifier: "invalid.cleanfile.type",
            fileExtension: "zip"
        )

        #expect(category == .archive)
    }

    /// 所选根目录不是其自身的子文件，不能生成子项相对路径。
    @Test("Relative path rejects the selected root itself")
    func relativePathRejectsRootItself() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)

        #expect(RelativePathComponents.make(fileURL: root, relativeTo: root) == nil)
    }

    /// 具有相同文本前缀的兄弟目录不应通过路径组件校验。
    @Test("Relative path rejects a sibling with a shared name prefix")
    func relativePathRejectsSiblingPrefix() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/tmp/RootBackup/file.txt")

        #expect(RelativePathComponents.make(fileURL: sibling, relativeTo: root) == nil)
    }

    /// 相对路径按组件保留中文、空格及文件名。
    @Test("Relative path preserves spaces and Unicode")
    func relativePathPreservesUserNames() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let file = root.appending(path: "资料/Project Files/报告.pdf")

        #expect(RelativePathComponents.make(fileURL: file, relativeTo: root) == [
            "资料", "Project Files", "报告.pdf"
        ])
    }

    /// 确认未知大小单独计数，不把缺失值误认为已知零字节。
    @Test("Unknown file sizes are excluded from total bytes")
    func unknownSizesAreExcludedFromTotals() {
        let summary = StorageSummary(files: [
            file("known.mov", category: .video, bytes: 1_000),
            file("cloud.mov", category: .video, bytes: 9_999, knownSize: false)
        ])

        #expect(summary.fileCount == 2)
        #expect(summary.totalBytes == 1_000)
        #expect(summary.unknownByteCountFileCount == 1)
        #expect(summary.categories.first(where: { $0.category == .video })?.unknownByteCount == 1)
    }

    /// 各分类的已知大小合计占总大小的百分之百，允许浮点误差。
    @Test("Category percentages sum to one when all sizes are known")
    func categoryPercentagesSumToOne() {
        let summary = StorageSummary(files: [
            file("one.mov", category: .video, bytes: 5),
            file("two.jpg", category: .image, bytes: 3),
            file("three.pdf", category: .pdf, bytes: 2)
        ])
        let sum = summary.categories.reduce(0) { $0 + $1.percentage }

        #expect(abs(sum - 1) < 0.000_001)
    }

    /// 非空分类列表不应显示文件数为零的类别。
    @Test("Non-empty categories omit zero-count categories")
    func nonEmptyCategoriesAreFiltered() {
        let summary = StorageSummary(files: [file("one.pdf", category: .pdf, bytes: 10)])

        #expect(summary.nonEmptyCategories.map { $0.category } == [.pdf])
    }

    /// 总大小为零时分类占比为零，避免除零导致无效数值。
    @Test("Zero-byte files do not produce invalid percentages")
    func zeroByteFilesHaveZeroPercentages() {
        let summary = StorageSummary(files: [file("empty.txt", category: .document, bytes: 0)])

        #expect(summary.totalBytes == 0)
        #expect(summary.categories.allSatisfy { $0.percentage == 0 })
    }

    /// 同一目录下的多个文件应共享目录节点并累计大小。
    @Test("File tree combines repeated directory branches")
    func fileTreeCombinesBranches() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let files = [
            file("A/one.pdf", category: .pdf, bytes: 10, root: root),
            file("A/two.jpg", category: .image, bytes: 20, root: root)
        ]
        let tree = FileTreeBuilder.build(rootURL: root, files: files)
        let branch = tree.children.first

        #expect(tree.children.count == 1)
        #expect(branch?.name == "A")
        #expect(branch?.children.count == 2)
        #expect(branch?.byteCount == 30)
    }

    /// 使用不同输入顺序构造目录树，验证结果顺序稳定。
    @Test("File tree is deterministic regardless of input ordering")
    func fileTreeOrderingIsDeterministic() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let alpha = file("Alpha/a.txt", category: .document, bytes: 1, root: root)
        let beta = file("Beta/b.txt", category: .document, bytes: 1, root: root)

        let forward = FileTreeBuilder.build(rootURL: root, files: [alpha, beta])
        let reverse = FileTreeBuilder.build(rootURL: root, files: [beta, alpha])

        #expect(forward == reverse)
    }

    /// 仅扫描中的状态标记为活动，空闲、取消和失败均不再扫描。
    @Test("Scan state activity flag only marks scanning")
    func scanStateActivityFlag() {
        let progress = ScanProgress(scannedFileCount: 1, scannedByteCount: 10)

        #expect(ScanState.scanning(progress).isScanning)
        #expect(!ScanState.idle.isScanning)
        #expect(!ScanState.cancelled.isScanning)
        #expect(!ScanState.failure(.unableToEnumerate).isScanning)
    }

    /// 删除结束后的成功或部分失败不应继续标记为删除中。
    @Test("File deletion activity flag only marks deleting")
    func fileDeletionActivityFlag() {
        #expect(FileDeletionState.deleting(itemCount: 3).isDeleting)
        #expect(!FileDeletionState.idle.isDeleting)
        #expect(!FileDeletionState.success(deletedCount: 3).isDeleting)
        #expect(!FileDeletionState.partialFailure(deletedCount: 1, failedCount: 2).isDeleting)
    }

    /// 列表身份基于文件 URL，使相同名称的不同路径可以区分。
    @Test("Scanned file identity is its URL")
    func scannedFileIdentityUsesURL() {
        let item = file("folder/item.txt", category: .document, bytes: 1)

        #expect(item.id == item.url)
    }

    /// 部分成功同时保留已删除的 URL 和失败数量，供上层更新状态。
    @Test("Deletion result retains partial success information")
    func deletionResultRetainsPartialSuccess() {
        let first = URL(fileURLWithPath: "/tmp/one")
        let result = FileDeletionResult(deletedURLs: [first], failedFileCount: 2)

        #expect(result.deletedURLs == [first])
        #expect(result.failedFileCount == 2)
    }

    /// 构造指定相对路径、分类和大小的扫描结果，供纯模型用例复用。
    private func file(
        _ path: String,
        category: FileCategory,
        bytes: Int64,
        knownSize: Bool = true,
        root: URL = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
    ) -> ScannedFile {
        ScannedFile(
            url: root.appending(path: path),
            name: URL(fileURLWithPath: path).lastPathComponent,
            relativePathComponents: path.split(separator: "/").map(String.init),
            category: category,
            byteCount: bytes,
            hasKnownByteCount: knownSize
        )
    }
}
