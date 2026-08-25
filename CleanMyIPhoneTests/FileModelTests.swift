import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CleanMyIPhone

@Suite("File model behavior")
struct FileModelTests {
    @Test("File extension matching is case insensitive")
    func extensionMatchingIsCaseInsensitive() {
        #expect(FileCategory.classify(fileExtension: "MOV") == .video)
        #expect(FileCategory.classify(fileExtension: "JpEg") == .image)
        #expect(FileCategory.classify(fileExtension: "PDF") == .pdf)
    }

    @Test("Supported audio extensions are classified")
    func audioExtensionsAreClassified() {
        for fileExtension in ["mp3", "m4a", "wav", "flac", "aac", "ogg"] {
            #expect(FileCategory.classify(fileExtension: fileExtension) == .audio)
        }
    }

    @Test("Supported document extensions are classified")
    func documentExtensionsAreClassified() {
        for fileExtension in ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "csv", "json"] {
            #expect(FileCategory.classify(fileExtension: fileExtension) == .document)
        }
    }

    @Test("Unknown and empty extensions remain other")
    func unknownExtensionsRemainOther() {
        #expect(FileCategory.classify(fileExtension: "") == .other)
        #expect(FileCategory.classify(fileExtension: "custom-format") == .other)
    }

    @Test("Type identifier takes priority over a misleading extension")
    func typeIdentifierTakesPriority() {
        #expect(FileCategory.classify(typeIdentifier: UTType.image.identifier, fileExtension: "txt") == .image)
        #expect(FileCategory.classify(typeIdentifier: UTType.audio.identifier, fileExtension: "pdf") == .audio)
    }

    @Test("Invalid type identifier falls back to extension")
    func invalidTypeIdentifierFallsBackToExtension() {
        let category = FileCategory.classify(
            typeIdentifier: "invalid.cleanfile.type",
            fileExtension: "zip"
        )

        #expect(category == .archive)
    }

    @Test("Relative path rejects the selected root itself")
    func relativePathRejectsRootItself() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)

        #expect(RelativePathComponents.make(fileURL: root, relativeTo: root) == nil)
    }

    @Test("Relative path rejects a sibling with a shared name prefix")
    func relativePathRejectsSiblingPrefix() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/tmp/RootBackup/file.txt")

        #expect(RelativePathComponents.make(fileURL: sibling, relativeTo: root) == nil)
    }

    @Test("Relative path preserves spaces and Unicode")
    func relativePathPreservesUserNames() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let file = root.appending(path: "资料/Project Files/报告.pdf")

        #expect(RelativePathComponents.make(fileURL: file, relativeTo: root) == [
            "资料", "Project Files", "报告.pdf"
        ])
    }

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

    @Test("Non-empty categories omit zero-count categories")
    func nonEmptyCategoriesAreFiltered() {
        let summary = StorageSummary(files: [file("one.pdf", category: .pdf, bytes: 10)])

        #expect(summary.nonEmptyCategories.map(\.category) == [.pdf])
    }

    @Test("Zero-byte files do not produce invalid percentages")
    func zeroByteFilesHaveZeroPercentages() {
        let summary = StorageSummary(files: [file("empty.txt", category: .document, bytes: 0)])

        #expect(summary.totalBytes == 0)
        #expect(summary.categories.allSatisfy { $0.percentage == 0 })
    }

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

    @Test("File tree is deterministic regardless of input ordering")
    func fileTreeOrderingIsDeterministic() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let alpha = file("Alpha/a.txt", category: .document, bytes: 1, root: root)
        let beta = file("Beta/b.txt", category: .document, bytes: 1, root: root)

        let forward = FileTreeBuilder.build(rootURL: root, files: [alpha, beta])
        let reverse = FileTreeBuilder.build(rootURL: root, files: [beta, alpha])

        #expect(forward == reverse)
    }

    @Test("Scan state activity flag only marks scanning")
    func scanStateActivityFlag() {
        let progress = ScanProgress(scannedFileCount: 1, scannedByteCount: 10)

        #expect(ScanState.scanning(progress).isScanning)
        #expect(!ScanState.idle.isScanning)
        #expect(!ScanState.cancelled.isScanning)
        #expect(!ScanState.failure(.unableToEnumerate).isScanning)
    }

    @Test("File deletion activity flag only marks deleting")
    func fileDeletionActivityFlag() {
        #expect(FileDeletionState.deleting(itemCount: 3).isDeleting)
        #expect(!FileDeletionState.idle.isDeleting)
        #expect(!FileDeletionState.success(deletedCount: 3).isDeleting)
        #expect(!FileDeletionState.partialFailure(deletedCount: 1, failedCount: 2).isDeleting)
    }

    @Test("Scanned file identity is its URL")
    func scannedFileIdentityUsesURL() {
        let item = file("folder/item.txt", category: .document, bytes: 1)

        #expect(item.id == item.url)
    }

    @Test("Deletion result retains partial success information")
    func deletionResultRetainsPartialSuccess() {
        let first = URL(fileURLWithPath: "/tmp/one")
        let result = FileDeletionResult(deletedURLs: [first], failedFileCount: 2)

        #expect(result.deletedURLs == [first])
        #expect(result.failedFileCount == 2)
    }

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
