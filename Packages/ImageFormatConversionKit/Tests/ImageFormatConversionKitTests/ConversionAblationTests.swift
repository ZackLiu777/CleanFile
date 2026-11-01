//
//  通过成对、轮换顺序的实验比较导入进度更新频率和图片批处理并发度。
//  固定测试文件和哈希用于验证优化前后内容及转换结果一致。
//  时间数据仅用于诊断，不以设备相关阈值判断性能。
//  导入比较完整、节流和不更新界面三种回调，图片批处理比较一至两个并发任务。
//  使用测试生成的临时文件；计时包含各场景明确选定的工作范围。
//

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageFormatConversionKit

/// Paired, warm-cache experiments; no device-specific performance assertions.
/// Diagnostic variants do not alter production defaults.
/// 对照不同进度回调和并发设置，同时验证结果与源文件完整性。
@Suite("Conversion ablation experiments", .serialized)
struct ConversionAblationTests {
    /// 轮换完整回调、节流回调和不更新界面的模式，并验证副本哈希。
    @Test("Ablate main-actor progress updates without changing the copy pipeline")
    func importProgressAblation() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = ConversionWorkspace(rootURL: root.appendingPathComponent("workspace"))
        for mib in [1, 32, 128] {
            let source = root.appendingPathComponent("fixture.bin")
            try writeFixture(source, mib: mib)
            let expectedHash = try digest(source)
            var samples = Array(repeating: [Double](), count: 3)
            for round in 0..<6 {
                // Rotate order to avoid always giving the same variant warmer caches.
                for offset in 0..<3 {
                    let mode = (round + offset) % 3
                    let sink = await MainActor.run { ProgressSink() }
                    let gate = ProgressGate()
                    let start = ContinuousClock.now
                    let (output, bytes) = try await workspace.stage(
                        source, id: UUID(), kind: .video
                    ) { copied, total in
                        if mode == 0 || (mode == 1 && gate.shouldPublish(copied, total)) {
                            await sink.receive(copied, total)
                        }
                    }
                    let elapsed = milliseconds(start.duration(to: .now))
                    if round > 0 { samples[mode].append(elapsed) }
                    #expect(bytes == Int64(mib * 1_048_576))
                    #expect(try digest(output) == expectedHash)
                    if mode != 2 {
                        let last = await sink.last
                        #expect(last == bytes)
                        #expect(await sink.isMonotonic)
                    }
                    print("ABLATION_SAMPLE import mib=\(mib) round=\(round) mode=\(mode) ms=\(elapsed) main_updates=\(await sink.count)")
                    try FileManager.default.removeItem(at: output.deletingLastPathComponent())
                }
            }
            report("import-\(mib)MiB-main-every", samples[0])
            report("import-\(mib)MiB-main-50ms", samples[1], baseline: samples[0])
            report("import-\(mib)MiB-no-main-diagnostic", samples[2], baseline: samples[0])
            #expect(try digest(source) == expectedHash)
        }
    }

    /// 比较一和两个并发转换任务，确认结果数量、尺寸、格式和哈希一致。
    @Test("Ablate a batch worker while preserving every image result")
    func imageConcurrencyAblation() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.png")
        try writeImage(source)
        let originalHash = try digest(source)
        var expectedOutputHash: SHA256.Digest?
        var samples = Array(repeating: [Double](), count: 2)
        for round in 0..<6 {
            for offset in 0..<2 {
                let mode = (round + offset) % 2
                let concurrency = mode == 0 ? 2 : 1
                let output = root.appendingPathComponent("outputs")
                let requests = (0..<8).map { index in
                    ImageConversionRequest(
                        sourceURL: source, destinationDirectory: output,
                        outputFormat: .jpeg, quality: 0.82, metadataPolicy: .removeAll,
                        preferredBaseName: "image-\(index)"
                    )
                }
                let start = ContinuousClock.now
                let result = await ImageBatchConverter().convert(requests, maxConcurrentConversions: concurrency)
                let elapsed = milliseconds(start.duration(to: .now))
                if round > 0 { samples[mode].append(elapsed) }
                #expect(result.successes.count == 8)
                #expect(result.failures.isEmpty)
                #expect(!result.wasCancelled)
                for item in result.successes {
                    let info = try await ImageConversionEngine().inspect(item.outputURL)
                    #expect(info.pixelWidth == 2048 && info.pixelHeight == 1536)
                    #expect(info.typeIdentifier == UTType.jpeg.identifier)
                    #expect(info.fileSizeBytes > 0)
                    // Worker count must not alter the encoded result for this fixed fixture.
                    let outputHash = try digest(item.outputURL)
                    if let expectedOutputHash {
                        #expect(outputHash == expectedOutputHash)
                    } else {
                        expectedOutputHash = outputHash
                    }
                }
                print("ABLATION_SAMPLE image round=\(round) concurrency=\(concurrency) ms=\(elapsed)")
                try FileManager.default.removeItem(at: output)
            }
        }
        #expect(try digest(source) == originalHash)
        report("image-batch-8-concurrency-2", samples[0])
        report("image-batch-8-concurrency-1", samples[1], baseline: samples[0])
    }

    /// 创建隔离的临时实验目录。
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConversionAblation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 分块生成确定性文件，供实验或压力转换使用。
    private func writeFixture(_ url: URL, mib: Int) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        let chunk = Data((0..<1_048_576).map { UInt8(truncatingIfNeeded: $0) })
        for _ in 0..<mib { try handle.write(contentsOf: chunk) }
        try handle.synchronize()
    }

    /// 分块计算文件 SHA-256，用于比较源与副本内容。
    private func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize()
    }

    /// 生成固定尺寸的合成图片作为转换输入。
    private func writeImage(_ url: URL) throws {
        let context = try #require(CGContext(
            data: nil, width: 2048, height: 1536, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for y in stride(from: 0, to: 1536, by: 16) {
            context.setFillColor(CGColor(red: CGFloat(y % 255) / 255, green: 0.4, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: 2048, height: 16))
        }
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// 将 Duration 转换为毫秒，便于报告实验结果。
    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// 输出实验样本的中位数、范围及相对基线变化，不断言运行时间。
    private func report(_ label: String, _ samples: [Double], baseline: [Double]? = nil) {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let base = baseline.map { $0.sorted()[$0.count / 2] } ?? median
        print("ABLATION_RESULT \(label) n=\(sorted.count) median_ms=\(median) min_ms=\(sorted[0]) max_ms=\(sorted[sorted.count - 1]) reduction_percent=\((base - median) / base * 100)")
    }
}

/// 在主执行域记录进度次数、最后值及其是否单调，供回调策略对照。
@MainActor
private final class ProgressSink {
    private(set) var last: Int64 = 0
    private(set) var count = 0
    private(set) var isMonotonic = true
    /// 接收一次进度并检查是否倒退或超过总字节数。
    func receive(_ copied: Int64, _ total: Int64) {
        isMonotonic = isMonotonic && copied >= last && copied <= total
        last = copied
        count += 1
    }
}

/// 使用锁串行化回调节流时间，模拟间隔发布进度的实验方案。
private final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last: ContinuousClock.Instant?
    /// 以锁保护时间状态，保留起点、终点及间隔达到阈值的进度。
    func shouldPublish(_ copied: Int64, _ total: Int64) -> Bool {
        lock.withLock {
            let now = ContinuousClock.now
            let intervalElapsed = last.map { $0.duration(to: now) >= .milliseconds(50) } ?? true
            guard copied == 0 || copied == total || intervalElapsed else { return false }
            last = now
            return true
        }
    }
}
