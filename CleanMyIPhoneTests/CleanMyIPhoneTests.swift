//
//  核心文件与媒体行为
//
//  覆盖文件分类、扫描、目录树、存储汇总、媒体结果和图表适配。
//  测试使用构造数据及临时目录，检查基础业务契约和目录层级。
//  包括分类结果的保护项、相对路径和目录深度，以及紧凑画布下的图表几何。
//  涉及扫描的用例创建独立临时目录，结束后清理测试数据。
//

//
//  CleanMyIPhoneTests.swift
//  CleanMyIPhoneTests
//
//  Created by Zane Liao on 8/18/26.
//

import Foundation
import Photos
import Testing
@testable import CleanMyIPhone

/// 核心模型、扫描和存储展示适配的基础回归用例。
struct CleanMyIPhoneTests {
    /// 验证一段视频可以同时因时长、分辨率和系统子类型进入多个分类。
    @Test
    func videoMetadataCanBelongToMultipleCategories() {
        let categories = MediaClassificationService.categories(
            duration: 12 * 60,
            pixelWidth: 3_840,
            pixelHeight: 2_160,
            mediaSubtypes: [.videoScreenRecording, .videoHighFrameRate]
        )

        #expect(categories == [.longDuration, .fourK, .screenRecording, .slowMotion])
    }

    /// 检查相似组保留建议保留项标识及组内资源信息。
    @Test
    func similarGroupTracksItsSuggestedKeeper() {
        let group = SimilarImageGroup(
            id: "group",
            items: [
                SimilarImageItem(
                    id: "keeper",
                    pixelWidth: 100,
                    pixelHeight: 100,
                    creationDate: nil
                ),
                SimilarImageItem(
                    id: "similar",
                    pixelWidth: 100,
                    pixelHeight: 100,
                    creationDate: nil
                )
            ],
            suggestedKeeperID: "keeper"
        )

        #expect(group.suggestedKeeperID == "keeper")
        #expect(group.items.count == 2)
    }

    /// 核对常见视频、图片、PDF 和压缩文件扩展名的分类。
    @Test
    func commonFileExtensionsAreClassified() {
        #expect(FileCategory.classify(fileExtension: "mp4") == .video)
        #expect(FileCategory.classify(fileExtension: "heic") == .image)
        #expect(FileCategory.classify(fileExtension: "pdf") == .pdf)
        #expect(FileCategory.classify(fileExtension: "zip") == .archive)
    }

    /// 用多个类别的文件检查汇总字节、数量及分类占比。
    @Test
    func storageSummaryAggregatesBytesAndCounts() {
        let files = [
            ScannedFile(
                url: URL(fileURLWithPath: "/tmp/video.mp4"),
                name: "video.mp4",
                relativePathComponents: ["video.mp4"],
                category: .video,
                byteCount: 2_000
            ),
            ScannedFile(
                url: URL(fileURLWithPath: "/tmp/photo.jpg"),
                name: "photo.jpg",
                relativePathComponents: ["photo.jpg"],
                category: .image,
                byteCount: 1_000
            )
        ]

        let summary = StorageSummary(files: files)

        #expect(summary.fileCount == 2)
        #expect(summary.totalBytes == 3_000)
        #expect(summary.categories.first(where: { $0.category == .video })?.byteCount == 2_000)
        #expect(summary.categories.first(where: { $0.category == .image })?.percentage == 1.0 / 3.0)
    }

    /// 空文件集合的总数、总字节和各类别占比均为零。
    @Test
    func emptyStorageSummaryHasZeroPercentages() {
        let summary = StorageSummary(files: [])

        #expect(summary.fileCount == 0)
        #expect(summary.totalBytes == 0)
        #expect(summary.categories.allSatisfy { $0.percentage == 0 })
    }

    /// 从所选根目录提取嵌套文件的相对路径，保留每一层目录。
    @Test
    func relativePathComponentsPreserveTheScannedHierarchy() {
        let rootURL = URL(fileURLWithPath: "/tmp/Root", isDirectory: true)
        let fileURL = rootURL.appending(path: "A/B/file.pdf")

        let components = RelativePathComponents.make(
            fileURL: fileURL,
            relativeTo: rootURL
        )

        #expect(components == ["A", "B", "file.pdf"])
    }

    @MainActor
    /// 构造多层临时目录，确认扫描器不会漏掉深层文件。
    @Test
    func metadataScannerRecursivelyFindsFilesAtEveryDirectoryDepth() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanMyIPhoneScanner-\(UUID().uuidString)", isDirectory: true)
        let nestedURL = rootURL
            .appendingPathComponent("A", isDirectory: true)
            .appendingPathComponent("B", isDirectory: true)

        try FileManager.default.createDirectory(
            at: nestedURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try Data([1]).write(to: rootURL.appendingPathComponent("root.txt"))
        try Data([2]).write(to: nestedURL.appendingPathComponent("deep.pdf"))

        let scanner = MetadataFileScanner(
            fileAccess: UnrestrictedFileAccess(),
            progressInterval: 1
        )
        var result: FileScanResult?

        for try await event in scanner.scan(directory: rootURL) {
            if case .completed(let scanResult) = event {
                result = scanResult
            }
        }

        #expect(result?.files.count == 2)
        #expect(result?.files.contains {
            $0.relativePathComponents == ["A", "B", "deep.pdf"]
        } == true)
        #expect(result?.fileTree.children.contains {
            $0.name == "A" && $0.children.first?.name == "B"
        } == true)
    }

    /// 检查文件树按目录层级汇总子文件大小。
    @Test
    func fileTreeAggregatesDirectorySizes() {
        let rootURL = URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true)
        let files = [
            ScannedFile(
                url: rootURL.appending(path: "Videos/movie.mp4"),
                name: "movie.mp4",
                relativePathComponents: ["Videos", "movie.mp4"],
                category: .video,
                byteCount: 8_000
            ),
            ScannedFile(
                url: rootURL.appending(path: "Documents/report.pdf"),
                name: "report.pdf",
                relativePathComponents: ["Documents", "report.pdf"],
                category: .pdf,
                byteCount: 2_000
            )
        ]

        let root = FileTreeBuilder.build(rootURL: rootURL, files: files)
        let videos = root.children.first(where: { $0.name == "Videos" })

        #expect(root.byteCount == 10_000)
        #expect(root.children.count == 2)
        #expect(videos?.byteCount == 8_000)
        #expect(videos?.children.first?.name == "movie.mp4")
    }

    /// 让 URL 与保存的相对路径形成区别，确认树结构以扫描记录为准。
    @Test
    func fileTreeUsesStoredRelativePathsInsteadOfReinferringURLs() {
        let rootURL = URL(fileURLWithPath: "/tmp/CloudDocs", isDirectory: true)
        let file = ScannedFile(
            url: URL(fileURLWithPath: "/tmp/FileProviderItem/movie.mp4"),
            name: "movie.mp4",
            relativePathComponents: ["Downloads", "Videos", "Movies", "movie.mp4"],
            category: .video,
            byteCount: 8_000
        )

        let root = FileTreeBuilder.build(rootURL: rootURL, files: [file])
        let downloads = root.children.first(where: { $0.name == "Downloads" })
        let videos = downloads?.children.first(where: { $0.name == "Videos" })
        let movies = videos?.children.first(where: { $0.name == "Movies" })

        #expect(downloads?.isDirectory == true)
        #expect(videos?.isDirectory == true)
        #expect(movies?.children.first?.name == "movie.mp4")
    }

    /// 用多层树核对诊断结果的最大深度和结构描述。
    @Test
    func treeDiagnosticsReportsTheActualHierarchyDepth() {
        let leaf = FileNode(
            id: "a/b/c",
            name: "C",
            byteCount: 10,
            children: [],
            category: .pdf,
            isDirectory: false
        )
        let branch = FileNode(
            id: "a/b",
            name: "B",
            byteCount: 10,
            children: [leaf],
            category: .pdf,
            isDirectory: true
        )
        let topLevelDirectory = FileNode(
            id: "a",
            name: "A",
            byteCount: 10,
            children: [branch],
            category: .pdf,
            isDirectory: true
        )
        let root = FileNode(
            id: ".",
            name: "Root",
            byteCount: 10,
            children: [topLevelDirectory],
            category: .pdf,
            isDirectory: true
        )

        #expect(FileTreeDiagnostics.maximumDepth(of: root) == 3)
    }

    @MainActor
    /// 验证图表适配保留目录层级并正确换算容量单位。
    @Test
    func customSunburstAdapterPreservesHierarchyAndConvertsBytesToGigabytes() {
        let file = FileNode(
            id: "folder/file.mov",
            name: "file.mov",
            byteCount: 500_000_000,
            children: [],
            category: .video,
            isDirectory: false
        )
        let folder = FileNode(
            id: "folder",
            name: "Folder",
            byteCount: 500_000_000,
            children: [file],
            category: .video,
            isDirectory: true
        )
        let root = FileNode(
            id: ".",
            name: "Root",
            byteCount: 500_000_000,
            children: [folder],
            category: .video,
            isDirectory: true
        )

        let adaptedTree = SunburstTreeAdapter.adapt(root)

        #expect(adaptedTree.rootNode.name == "Root")
        #expect(adaptedTree.rootNode.children?.first?.name == "Folder")
        #expect(adaptedTree.rootNode.children?.first?.children?.first?.name == "file.mov")
        #expect(adaptedTree.rootNode.totalByteCount == 500_000_000)
        #expect(adaptedTree.rootNode.maximumDepth == 2)
        #expect(adaptedTree.sourceNodes.count == 3)
    }

    /// 检查小画布内十二层旭日图的半径与分层几何约束。
    @Test
    func customSunburstGeometryFitsTheCompleteDepthInsideACompactCanvas() {
        let canvasSize = CGSize(width: 280, height: 280)
        let maximumDepth = 12
        let geometry = SunburstChartGeometry(
            size: canvasSize,
            maximumDepth: maximumDepth
        )
        let outermostRing = geometry.radii(at: maximumDepth)
        let availableRadius = min(canvasSize.width, canvasSize.height) / 2

        #expect(outermostRing.outer <= availableRadius)
        #expect(geometry.maximumDepth == maximumDepth)
        #expect(geometry.centerRadius > 0)
        #expect(geometry.innerRingWidth > geometry.outerRingWidth)
    }

    /// 检查不足一 GB 的容量使用可读的 MB 值，较大容量使用 GB。
    @Test
    func sunburstCapacityNeverRoundsReadableFilesDownToZeroGigabytes() {
        let megabytes = SunburstCapacityFormatter.text(for: 48_300_000)
        let gigabytes = SunburstCapacityFormatter.text(for: 1_500_000_000)

        #expect(megabytes.value == "48.3")
        #expect(megabytes.unit == "MB")
        #expect(gigabytes.value == "1.50")
        #expect(gigabytes.unit == "GB")
    }
}
