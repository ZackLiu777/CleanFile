//
//  记录音频、图片、流式导入和清单持久化的性能基线。
//  测试自行生成固定素材并验证结果，同时报告耗时和吞吐量。
//  不为不同设备或 CI 负载设置固定性能通过阈值。
//  分别观察音频编码、图片转换、分段暂存和工作区清单的阶段成本。
//  工作区和素材由测试创建于临时目录，结束后清理。
//

import Dispatch
import AVFAudio
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageFormatConversionKit

/// Non-blocking baselines: timings are reported for comparison, while only
/// correctness is asserted because simulator and CI load are variable.
/// 使用可重复素材记录转换与工作区操作的基线。
@Suite("Conversion performance baselines", .serialized)
struct ConversionPerformanceBaselineTests {
    /// 生成固定时长 PCM 并记录音频编码吞吐量，同时检查输出。
    @Test("Thirty-second PCM audio conversion reports encoding throughput")
    func audioConversionThroughput() async throws {
        let fixture = try PerformanceWorkspaceFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.outputRoot,
            withIntermediateDirectories: true
        )
        let source = fixture.root.appending(path: "thirty-seconds.wav")
        try Self.writePCMFixture(to: source, durationSeconds: 30)
        let engine = AudioConversionEngine()

        let started = DispatchTime.now().uptimeNanoseconds
        let output = try await engine.convert(
            AudioConversionRequest(
                sourceURL: source,
                destinationDirectory: fixture.outputRoot,
                outputFormat: .aac,
                bitRate: .high
            )
        ) { _ in }
        let milliseconds = Self.milliseconds(since: started)
        let outputBytes = Int64((try output.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)

        print(String(
            format: "PERF_BASELINE conversion-audio media_seconds=30 output_bytes=%lld duration_ms=%.2f realtime_factor=%.2f",
            outputBytes,
            milliseconds,
            30 / max(milliseconds / 1_000, 0.000_001)
        ))
        #expect(outputBytes > 0)
    }

    /// 生成固定尺寸 JPEG 并记录图片转换耗时，同时检查输出。
    @Test("Six-megapixel JPEG conversion reports decode, encode, and commit cost")
    func imageConversionThroughput() async throws {
        let fixture = try PerformanceWorkspaceFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.outputRoot,
            withIntermediateDirectories: true
        )
        let source = fixture.root.appending(path: "six-megapixel.jpg")
        try Self.writeJPEGFixture(to: source, width: 3_000, height: 2_000)
        let sourceBytes = Int64((try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        let engine = ImageConversionEngine()

        let started = DispatchTime.now().uptimeNanoseconds
        let result = try await engine.convert(ImageConversionRequest(
            sourceURL: source,
            destinationDirectory: fixture.outputRoot,
            outputFormat: .jpeg,
            quality: 0.82,
            metadataPolicy: .removeAll
        ))
        let milliseconds = Self.milliseconds(since: started)

        print(String(
            format: "PERF_BASELINE conversion-image pixels=%d source_bytes=%lld output_bytes=%lld duration_ms=%.2f megapixels_per_second=%.2f",
            6_000_000,
            sourceBytes,
            result.outputBytes,
            milliseconds,
            6 / max(milliseconds / 1_000, 0.000_001)
        ))
        #expect(result.pixelWidth == 3_000)
        #expect(result.pixelHeight == 2_000)
        #expect(result.outputBytes > 0)
    }

    /// 暂存不同大小的合成文件，记录流式导入吞吐量。
    @Test("Streaming import reports throughput for representative large files")
    func streamingImportThroughput() async throws {
        let fixture = try PerformanceWorkspaceFixture()
        defer { fixture.remove() }

        for byteCount in [8 * 1_048_576, 32 * 1_048_576] {
            let source = fixture.root.appending(path: "source-\(byteCount).bin")
            try Self.createFile(at: source, byteCount: byteCount)
            let workspace = ConversionWorkspace(rootURL: fixture.workspaceRoot)

            let started = DispatchTime.now().uptimeNanoseconds
            let (destination, stagedBytes) = try await workspace.stage(
                source,
                id: UUID(),
                kind: .video
            ) { _, _ in }
            let milliseconds = Self.milliseconds(since: started)

            print(Self.throughputReport(
                name: "conversion-import",
                byteCount: byteCount,
                durationMilliseconds: milliseconds
            ))
            #expect(stagedBytes == Int64(byteCount))
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    /// 保存并恢复工作区清单，报告持久化开销。
    @Test("Workspace manifest reports save and restore costs")
    func manifestPersistenceCost() async throws {
        let fixture = try PerformanceWorkspaceFixture()
        defer { fixture.remove() }
        let source = fixture.root.appending(path: "existing.bin")
        try Data([0xA5]).write(to: source)
        let records = (0 ..< 2_000).map { index in
            PersistedConversionItem(
                id: UUID(),
                sourcePath: source.path,
                sourceBytes: Int64(index + 1),
                status: .ready,
                outputPath: nil
            )
        }
        let workspace = ConversionWorkspace(rootURL: fixture.workspaceRoot)

        var started = DispatchTime.now().uptimeNanoseconds
        await workspace.save(records, kind: .image)
        let saveMilliseconds = Self.milliseconds(since: started)

        started = DispatchTime.now().uptimeNanoseconds
        let restored = await workspace.load(.image)
        let loadMilliseconds = Self.milliseconds(since: started)

        print(Self.latencyReport(
            name: "conversion-manifest-save",
            itemCount: records.count,
            durationMilliseconds: saveMilliseconds
        ))
        print(Self.latencyReport(
            name: "conversion-manifest-load",
            itemCount: records.count,
            durationMilliseconds: loadMilliseconds
        ))
        #expect(restored.count == records.count)
    }

    /// 以固定字节分块写入指定大小的合成文件，避免一次构造整份大文件。
    private static func createFile(at url: URL, byteCount: Int) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let chunk = Data(repeating: 0xA5, count: 1_048_576)
        var remaining = byteCount
        while remaining > 0 {
            let count = min(remaining, chunk.count)
            try handle.write(contentsOf: count == chunk.count ? chunk : chunk.prefix(count))
            remaining -= count
        }
        try handle.synchronize()
    }

    /// 生成确定尺寸和像素图案的 JPEG，用于图片转换基线。
    private static func writeJPEGFixture(to url: URL, width: Int, height: Int) throws {
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let offset = y * bytesPerRow + x * 4
                    bytes[offset] = UInt8(truncatingIfNeeded: x)
                    bytes[offset + 1] = UInt8(truncatingIfNeeded: y)
                    bytes[offset + 2] = UInt8(truncatingIfNeeded: x + y)
                    bytes[offset + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              )
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// 分块生成 44.1 kHz 双声道 PCM 正弦波，作为音频转换输入。
    private static func writePCMFixture(to url: URL, durationSeconds: Int) throws {
        let sampleRate = 44_100.0
        let channels: AVAudioChannelCount = 2
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let totalFrames = AVAudioFramePosition(sampleRate * Double(durationSeconds))
        let chunkFrames: AVAudioFrameCount = 16_384
        var written: AVAudioFramePosition = 0
        while written < totalFrames {
            let frameCount = AVAudioFrameCount(min(
                AVAudioFramePosition(chunkFrames),
                totalFrames - written
            ))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
            buffer.frameLength = frameCount
            if let channelData = buffer.floatChannelData {
                for channel in 0 ..< Int(channels) {
                    for frame in 0 ..< Int(frameCount) {
                        let position = Double(written + AVAudioFramePosition(frame))
                        channelData[channel][frame] = Float(sin(2 * .pi * 440 * position / sampleRate) * 0.2)
                    }
                }
            }
            try output.write(from: buffer)
            written += AVAudioFramePosition(frameCount)
        }
    }

    /// 根据单调时钟的纳秒起点计算经过的毫秒数。
    private static func milliseconds(since started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    /// 将文件大小与耗时格式化为 MiB 每秒，零耗时时报告零吞吐量。
    private static func throughputReport(
        name: String,
        byteCount: Int,
        durationMilliseconds: Double
    ) -> String {
        let megabytes = Double(byteCount) / 1_048_576
        let seconds = durationMilliseconds / 1_000
        let throughput = seconds > 0 ? megabytes / seconds : 0
        return String(
            format: "PERF_BASELINE %@ bytes=%d duration_ms=%.2f throughput_mib_s=%.2f",
            name,
            byteCount,
            durationMilliseconds,
            throughput
        )
    }

    /// 格式化清单保存或恢复的项目数和耗时，供基线对照。
    private static func latencyReport(
        name: String,
        itemCount: Int,
        durationMilliseconds: Double
    ) -> String {
        String(
            format: "PERF_BASELINE %@ items=%d duration_ms=%.2f",
            name,
            itemCount,
            durationMilliseconds
        )
    }
}

/// 提供独立的临时工作区及输出路径，避免性能样本相互干扰。
private struct PerformanceWorkspaceFixture {
    let root: URL
    let workspaceRoot: URL
    let outputRoot: URL

    /// 创建临时根目录，记录工作区和输出子目录的位置。
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "Conversion-Performance-\(UUID().uuidString)", directoryHint: .isDirectory)
        workspaceRoot = root.appending(path: "Workspace", directoryHint: .isDirectory)
        outputRoot = root.appending(path: "Outputs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 尽力清理本次性能样本使用的临时文件。
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
