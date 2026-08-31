import Foundation
import Testing
@testable import CleanMyIPhone

@Suite("Storage model contracts")
struct StorageModelContractExhaustiveTests {
    @Test("Every file category has a stable display name")
    func fileCategoryDisplayNamesAreNonEmpty() {
        for category in FileCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }

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

@Suite("Media model contracts")
struct MediaModelContractExhaustiveTests {
    @Test("Device storage snapshot clamps impossible capacities safely")
    func deviceStorageSnapshotClampsImpossibleValues() {
        let overAvailable = DeviceStorageSnapshot(totalBytes: 100, availableBytes: 200)
        let negativeCapacity = DeviceStorageSnapshot(totalBytes: -100, availableBytes: 20)

        #expect(overAvailable.usedBytes == 0)
        #expect(overAvailable.usedFraction == 0)
        #expect(negativeCapacity.usedBytes == 0)
        #expect(negativeCapacity.usedFraction == 0)
    }

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

    @Test("Every video category has a readable display name")
    func videoCategoryDisplayNamesAreNonEmpty() {
        for category in VideoCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }

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
