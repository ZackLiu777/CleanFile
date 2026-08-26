import Foundation
import Testing
@testable import ImageFormatConversionKit

@Suite("Conversion import progress")
struct ConversionImportProgressTests {
    @Test("Combined file progress reaches an accurate percentage")
    func percentageCalculation() {
        let halfwayThroughSecondFile = ConversionImportProgress(
            completed: 1,
            total: 2,
            currentFileName: "large.mov",
            currentFileFraction: 0.5
        )
        let completed = ConversionImportProgress(
            completed: 2,
            total: 2,
            currentFileName: nil
        )

        #expect(halfwayThroughSecondFile.fractionCompleted == 0.75)
        #expect(halfwayThroughSecondFile.percentage == 75)
        #expect(completed.fractionCompleted == 1)
        #expect(completed.percentage == 100)
    }

    @Test("Large file staging reports intermediate byte progress before completion")
    func largeFileReportsIncrementalProgress() async throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("conversion-progress-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        let sourceURL = testRoot.appendingPathComponent("large-source.mov")
        let sourceData = Data(repeating: 0xA5, count: 3 * 1_048_576 + 257)
        try sourceData.write(to: sourceURL, options: .atomic)

        let workspace = ConversionWorkspace(
            fileManager: fileManager,
            rootURL: testRoot.appendingPathComponent("workspace", isDirectory: true)
        )
        let recorder = ImportProgressRecorder()
        let (destination, stagedBytes) = try await workspace.stage(
            sourceURL,
            id: UUID(),
            kind: .video
        ) { copiedBytes, totalBytes in
            await recorder.append(copiedBytes: copiedBytes, totalBytes: totalBytes)
        }
        let samples = await recorder.samples

        #expect(stagedBytes == Int64(sourceData.count))
        #expect(fileManager.fileExists(atPath: destination.path))
        #expect(samples.first?.copiedBytes == 0)
        #expect(samples.contains { sample in
            sample.copiedBytes > 0 && sample.copiedBytes < sample.totalBytes
        })
        #expect(samples.last?.copiedBytes == Int64(sourceData.count))
        #expect(samples.last?.totalBytes == Int64(sourceData.count))
    }
}

private actor ImportProgressRecorder {
    struct Sample: Sendable {
        let copiedBytes: Int64
        let totalBytes: Int64
    }

    private(set) var samples: [Sample] = []

    func append(copiedBytes: Int64, totalBytes: Int64) {
        samples.append(Sample(copiedBytes: copiedBytes, totalBytes: totalBytes))
    }
}
