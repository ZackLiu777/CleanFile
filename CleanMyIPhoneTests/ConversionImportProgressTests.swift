//
//  转换导入进度
//
//  覆盖多文件汇总百分比和大文件暂存时的增量进度。
//  使用临时数据与隔离的记录器验证过程，不依赖用户文件。
//  大文件暂存用例验证开始、中间及最终字节回调，而非只检查最终结果。
//  记录器以 actor 隔离回调状态；测试文件位于单独创建并清理的临时目录。
//

import Foundation
import Testing
@testable import ImageFormatConversionKit

/// 验证导入进度的合并计算和大文件分段反馈。
@Suite("Conversion import progress")
struct ConversionImportProgressTests {
    /// 检查多文件的已完成字节与总字节合并后得到的百分比。
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

    /// 使用较大临时文件确认复制完成前会收到中间字节进度。
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

/// 隔离异步进度回调，保存测试中观察到的字节进度。
private actor ImportProgressRecorder {
    /// 保存一次回调中的累计复制字节与目标总字节，供异步测试检查进度序列。
    struct Sample: Sendable {
        let copiedBytes: Int64
        let totalBytes: Int64
    }

    private(set) var samples: [Sample] = []

    /// 将回调快照追加到 actor 隔离的序列，避免并发回调竞争测试状态。
    func append(copiedBytes: Int64, totalBytes: Int64) {
        samples.append(Sample(copiedBytes: copiedBytes, totalBytes: totalBytes))
    }
}
