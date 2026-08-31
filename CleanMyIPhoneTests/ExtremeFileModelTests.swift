import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CleanMyIPhone

@Suite("File model edge cases")
struct ExtremeFileModelTests {
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

    @Test("Unrecognized extension input is safe for whitespace, dot files, and Unicode")
    func malformedExtensionsRemainOther() {
        for value in ["", ".jpg", " jpg ", "文件.未知", "nil", "MP4.tmp"] {
            #expect(FileCategory.classify(fileExtension: value) == .other)
        }
    }

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

    @Test("Relative path accepts a deeply nested Unicode file")
    func relativePathHandlesDeepUnicodeHierarchy() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let file = root.appending(path: "一/二/三/四/最终 文件.mov")

        #expect(RelativePathComponents.make(fileURL: file, relativeTo: root) == [
            "一", "二", "三", "四", "最终 文件.mov"
        ])
    }

    @Test("Relative path rejects traversal-like components")
    func relativePathRejectsTraversalComponents() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let rootComponents = root.pathComponents

        #expect(RelativePathComponents.make(
            fileURL: root.appending(path: "../outside.txt"),
            rootComponents: rootComponents
        ) == nil)
        #expect(RelativePathComponents.make(
            fileURL: root.appending(path: "./file.txt"),
            rootComponents: rootComponents
        ) == ["file.txt"])
    }

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

    @Test("Empty tree uses a safe selected-folder name")
    func emptyTreeHasStableRoot() {
        let root = URL(fileURLWithPath: "/")
        let tree = FileTreeBuilder.build(rootURL: root, files: [])

        #expect(tree.id == ".")
        #expect(tree.isDirectory)
        #expect(tree.children.isEmpty)
        #expect(FileTreeDiagnostics.maximumDepth(of: tree) == 0)
    }

    @Test("Tree dominant category follows the largest child branch")
    func treeDominantCategoryUsesLargestBranch() {
        let root = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let files = [
            ScannedFile(url: root.appending(path: "small.pdf"), name: "small.pdf", relativePathComponents: ["small.pdf"], category: .pdf, byteCount: 1),
            ScannedFile(url: root.appending(path: "large.mp4"), name: "large.mp4", relativePathComponents: ["large.mp4"], category: .video, byteCount: 10)
        ]

        #expect(FileTreeBuilder.build(rootURL: root, files: files).category == .video)
    }

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

    @Test("Largest-files ties use a deterministic localized name order")
    func largestAccumulatorSortsTiesByName() {
        var accumulator = LargestFilesAccumulator(limit: 3)
        accumulator.append(makeFile(name: "zeta", bytes: 42))
        accumulator.append(makeFile(name: "alpha", bytes: 42))
        accumulator.append(makeFile(name: "middle", bytes: 42))

        #expect(accumulator.sortedDescending().map { $0.name } == ["alpha", "middle", "zeta"])
    }

    @Test("Storage summary preserves all category slots for an empty input")
    func emptySummaryPreservesCategoryShape() {
        let summary = StorageSummary(files: [])

        #expect(summary.fileCount == 0)
        #expect(summary.categories.map { $0.category } == FileCategory.allCases)
        #expect(summary.nonEmptyCategories.isEmpty)
    }

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
