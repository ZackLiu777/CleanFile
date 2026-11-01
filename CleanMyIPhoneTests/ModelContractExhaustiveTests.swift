//
//  模型契约完整性
//
//  覆盖存储与媒体值模型的展示、状态、错误和编码契约。
//  使用边界输入检查未知大小、异常容量和可选元数据。
//  检查已知大小优先排序、未知字节统计、错误描述及可选日期的编码往返。
//  所有文件与媒体记录均在内存中构造，示例 URL 不用于读取文件。
//

import Foundation
import Testing
@testable import CleanMyIPhone

/// 验证存储领域模型的状态、错误、显示和序列化契约。
@Suite("Storage model contracts")
struct StorageModelContractExhaustiveTests {
    /// 遍历所有文件类别，确保每一项都能提供非空展示名。
    @Test("Every file category has a stable display name")
    func fileCategoryDisplayNamesAreNonEmpty() {
        for category in FileCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }

    /// 即使未知大小的占位数值更大，也必须排在已知大小之后。
    @Test("File display order keeps known sizes before unknown sizes")
    func displayOrderPrioritizesKnownSizes() {
        let files = [
            makeFile("unknown.bin", bytes: 10_000, known: false),
            makeFile("small.txt", bytes: 100),
            makeFile("large.mp4", bytes: 900)
        ]

        let sorted = FileDisplayOrder.bySizeDescending(files)

        #expect(sorted.map { $0.name } == ["large.mp4", "small.txt", "unknown.bin"])
    }

    /// 验证未知大小数量单独统计，不参与已知字节总量。
    @Test("Summary accumulator separates unknown bytes from known totals")
    func summaryAccumulatorTracksUnknownBytes() {
        var accumulator = StorageSummaryAccumulator()
        accumulator.append(makeFile("movie.mp4", bytes: 1_000, category: .video))
        accumulator.append(makeFile("cloud.mov", bytes: 9_000, category: .video, known: false))
        accumulator.append(makeFile("photo.jpg", bytes: 3_000, category: .image))

        let summary = accumulator.makeSummary()
        let video = summary.categories.first { $0.category == .video }

        #expect(summary.fileCount == 3)
        #expect(summary.totalBytes == 4_000)
        #expect(summary.unknownByteCountFileCount == 1)
        #expect(video?.fileCount == 2)
        #expect(video?.byteCount == 1_000)
        #expect(video?.unknownByteCount == 1)
        #expect(video?.percentage == 0.25)
    }

    /// 比较零层和两层诊断输出，验证深度限制不会隐藏根节点摘要。
    @Test("Tree diagnostics honor the requested print depth")
    func treeDiagnosticsRespectDepthLimit() {
        let leaf = FileNode(
            id: "folder/leaf.txt",
            name: "leaf.txt",
            byteCount: 10,
            children: [],
            category: .document,
            isDirectory: false
        )
        let folder = FileNode(
            id: "folder",
            name: "folder",
            byteCount: 10,
            children: [leaf],
            category: .document,
            isDirectory: true
        )
        let root = FileNode(
            id: ".",
            name: "Root",
            byteCount: 10,
            children: [folder],
            category: .document,
            isDirectory: true
        )

        let shallow = FileTreeDiagnostics.debugDescription(of: root, maximumPrintedDepth: 0)
        let detailed = FileTreeDiagnostics.debugDescription(of: root, maximumPrintedDepth: 2)

        #expect(shallow.contains("Root children = 1"))
        #expect(!shallow.contains("folder children"))
        #expect(detailed.contains("folder children = 1"))
        #expect(detailed.contains("leaf.txt children = 0"))
    }

    /// 枚举扫描及删除的各个状态，只有进行中状态的活动标记为真。
    @Test("Scan and deletion state activity flags are mutually exclusive")
    func stateActivityFlagsAreExclusive() {
        let summary = StorageSummary(files: [])
        let scanStates: [ScanState] = [
            .idle,
            .scanning(ScanProgress(scannedFileCount: 1, scannedByteCount: 2)),
            .success(summary),
            .empty,
            .partialFailure(summary, skippedFileCount: 1),
            .cancelled,
            .failure(.unableToEnumerate)
        ]
        let deletionStates: [FileDeletionState] = [
            .idle,
            .deleting(itemCount: 1),
            .success(deletedCount: 1),
            .partialFailure(deletedCount: 1, failedCount: 1),
            .failure(.deletionFailed)
        ]

        #expect(scanStates.map { $0.isScanning } == [false, true, false, false, false, false, false])
        #expect(deletionStates.map { $0.isDeleting } == [false, true, false, false, false])
    }

    /// 检查扫描和删除错误的每个列举情形均有可展示的描述。
    @Test("Storage errors expose descriptions for every case")
    func storageErrorsHaveDescriptions() {
        let scanErrors: [FileScanError] = [
            .cancelled,
            .notDirectory,
            .unableToEnumerate,
            .securityScopeUnavailable,
            .selectionFailed
        ]
        let deletionErrors: [FileDeletionError] = [
            .noItemsSelected,
            .folderAccessUnavailable,
            .invalidSelection,
            .deletionFailed
        ]

        #expect(scanErrors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
        #expect(deletionErrors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    /// 编码往返保留可选日期与大小未知标记。
    @Test("Scanned file Codable keeps optional metadata and unknown size flags")
    func scannedFileCodablePreservesMetadata() throws {
        let creationDate = Date(timeIntervalSince1970: 123)
        let modificationDate = Date(timeIntervalSince1970: 456)
        let file = makeFile(
            "report.pdf",
            bytes: 500,
            category: .pdf,
            known: false,
            creationDate: creationDate,
            modificationDate: modificationDate
        )

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ScannedFile.self, from: data)

        #expect(decoded == file)
        #expect(decoded.id == decoded.url)
        #expect(decoded.creationDate == creationDate)
        #expect(decoded.modificationDate == modificationDate)
    }

    /// 生成可配置类别、大小状态和日期的内存文件记录，用于模型契约检查。
    private func makeFile(
        _ name: String,
        bytes: Int64,
        category: FileCategory = .other,
        known: Bool = true,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) -> ScannedFile {
        let url = URL(fileURLWithPath: "/tmp/contract-tests/\(name)")
        return ScannedFile(
            url: url,
            name: name,
            relativePathComponents: [name],
            category: category,
            byteCount: bytes,
            hasKnownByteCount: known,
            creationDate: creationDate,
            modificationDate: modificationDate
        )
    }
}

/// 验证媒体容量、错误、视频类别和分类结果契约。
@Suite("Media model contracts")
struct MediaModelContractExhaustiveTests {
    /// 异常容量也必须产生受约束的可展示占比。
    @Test("Device storage snapshot clamps impossible capacities safely")
    func deviceStorageSnapshotClampsImpossibleValues() {
        let overAvailable = DeviceStorageSnapshot(totalBytes: 100, availableBytes: 200)
        let negativeCapacity = DeviceStorageSnapshot(totalBytes: -100, availableBytes: 20)

        #expect(overAvailable.usedBytes == 0)
        #expect(overAvailable.usedFraction == 0)
        #expect(negativeCapacity.usedBytes == 0)
        #expect(negativeCapacity.usedFraction == 0)
    }

    /// 检查媒体分析与删除错误均提供非空描述。
    @Test("Media analysis and deletion error descriptions cover every case")
    func mediaErrorsHaveDescriptions() {
        let analysisErrors: [MediaAnalysisError] = [.photoAccessUnavailable, .unexpected]
        let deletionErrors: [MediaDeletionError] = [
            .photoAccessUnavailable,
            .noItemsSelected,
            .itemsUnavailable,
            .deletionFailed
        ]

        #expect(analysisErrors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
        #expect(deletionErrors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    /// 遍历视频分类，确认所有类别均有展示名。
    @Test("Every video category has a readable display name")
    func videoCategoryDisplayNamesAreNonEmpty() {
        for category in VideoCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }

    /// 检查相似组与视频标识的展开结果，并确认分类计数只包含匹配标签。
    @Test("Media result exposes flattened identifiers and category counts")
    func mediaResultFlattensIdentifiers() {
        let first = SimilarImageItem(id: "first", pixelWidth: 100, pixelHeight: 100, creationDate: nil)
        let second = SimilarImageItem(id: "second", pixelWidth: 90, pixelHeight: 90, creationDate: nil)
        let video = ClassifiedVideo(
            id: "video",
            duration: 120,
            pixelWidth: 1_920,
            pixelHeight: 1_080,
            categories: [.longDuration, .fourK]
        )
        let result = MediaClassificationResult(
            similarImageGroups: [SimilarImageGroup(id: "group", items: [first, second], suggestedKeeperID: "first")],
            classifiedVideos: [video],
            screenshotIDs: ["screen"],
            livePhotoIDs: ["live"],
            skippedImageCount: 2
        )

        #expect(result.videoIDs == ["video"])
        #expect(result.similarImageIDs == ["first", "second"])
        #expect(result.similarImageCount == 2)
        #expect(result.videoCount(in: .longDuration) == 1)
        #expect(result.videoCount(in: .screenRecording) == 0)
    }
}
