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

struct CleanMyIPhoneTests {
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

    @Test
    func commonFileExtensionsAreClassified() {
        #expect(FileCategory.classify(fileExtension: "mp4") == .video)
        #expect(FileCategory.classify(fileExtension: "heic") == .image)
        #expect(FileCategory.classify(fileExtension: "pdf") == .pdf)
        #expect(FileCategory.classify(fileExtension: "zip") == .archive)
    }

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

    @Test
    func emptyStorageSummaryHasZeroPercentages() {
        let summary = StorageSummary(files: [])

        #expect(summary.fileCount == 0)
        #expect(summary.totalBytes == 0)
        #expect(summary.categories.allSatisfy { $0.percentage == 0 })
    }

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
