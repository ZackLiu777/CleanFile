import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageFormatConversionKit

/// Paired, warm-cache experiments; no device-specific performance assertions.
/// Diagnostic variants do not alter production defaults.
@Suite("Conversion ablation experiments", .serialized)
struct ConversionAblationTests {
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

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConversionAblation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeFixture(_ url: URL, mib: Int) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        let chunk = Data((0..<1_048_576).map { UInt8(truncatingIfNeeded: $0) })
        for _ in 0..<mib { try handle.write(contentsOf: chunk) }
        try handle.synchronize()
    }

    private func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize()
    }

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

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private func report(_ label: String, _ samples: [Double], baseline: [Double]? = nil) {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let base = baseline.map { $0.sorted()[$0.count / 2] } ?? median
        print("ABLATION_RESULT \(label) n=\(sorted.count) median_ms=\(median) min_ms=\(sorted[0]) max_ms=\(sorted[sorted.count - 1]) reduction_percent=\((base - median) / base * 100)")
    }
}

@MainActor
private final class ProgressSink {
    private(set) var last: Int64 = 0
    private(set) var count = 0
    private(set) var isMonotonic = true
    func receive(_ copied: Int64, _ total: Int64) {
        isMonotonic = isMonotonic && copied >= last && copied <= total
        last = copied
        count += 1
    }
}

private final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last: ContinuousClock.Instant?
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
