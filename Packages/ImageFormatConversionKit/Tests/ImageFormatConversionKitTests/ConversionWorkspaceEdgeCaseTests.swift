//
//  验证工作区文件暂存、清单恢复和受限范围清理。
//  覆盖已暂存、空文件、缺失源文件以及输出删除等边界。
//  使用临时目录与记录器检查文件内容、进度及清理结果。
//  清单恢复忽略已消失的源文件，删除记录只能清理允许范围内的暂存及输出。
//  所有文件均由测试工作区创建；字节进度由隔离记录器收集。
//

import Foundation
import Testing
@testable import ImageFormatConversionKit

/// 检查暂存与清理在文件缺失和目录边界下的行为。
@Suite("Conversion workspace edge cases")
struct ConversionWorkspaceEdgeCaseTests {
    /// 检查外部源文件复制到工作区并报告字节进度。
    @Test("Staging copies external files and reports byte progress")
    func stagingCopiesExternalFile() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let source = fixture.root.appending(path: "source.bin")
        try Data(repeating: 0xA5, count: 32_768).write(to: source)
        let recorder = ProgressRecorder()
        let workspace = ConversionWorkspace(rootURL: fixture.workspaceRoot)

        let (destination, bytes) = try await workspace.stage(
            source,
            id: UUID(),
            kind: .video
        ) { copied, total in
            await recorder.append(copied: copied, total: total)
        }
        let progress = await recorder.values

        #expect(bytes == 32_768)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let copiedData = try Data(contentsOf: destination)
        #expect(copiedData == Data(repeating: 0xA5, count: 32_768))
        #expect(progress.first?.copied == 0)
        #expect(progress.last?.copied == 32_768)
        #expect(progress.last?.total == 32_768)
    }

    /// 重复暂存工作区内文件时检查复用原路径。
    @Test("Staging an already-imported file is idempotent")
    func stagingImportedFileReturnsSameURL() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let imported = fixture.workspaceRoot
            .appending(path: "Imports/image/existing", directoryHint: .isDirectory)
            .appending(path: "photo.png")
        try FileManager.default.createDirectory(
            at: imported.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1, 2, 3]).write(to: imported)
        let recorder = ProgressRecorder()
        let workspace = ConversionWorkspace(rootURL: fixture.workspaceRoot)

        let (destination, bytes) = try await workspace.stage(
            imported,
            id: UUID(),
            kind: .image
        ) { copied, total in
            await recorder.append(copied: copied, total: total)
        }

        #expect(destination.standardizedFileURL == imported.standardizedFileURL)
        #expect(bytes == 3)
        let progress = await recorder.values
        #expect(progress.count == 1)
        #expect(progress.first?.copied == 3)
        #expect(progress.first?.total == 3)
    }

    /// 空文件暂存后仍存在，返回零字节且内容为空。
    @Test("Empty files stage successfully with a zero-byte result")
    func stagingEmptyFileProducesZeroBytes() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let source = fixture.root.appending(path: "empty.dat")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        let workspace = ConversionWorkspace(rootURL: fixture.workspaceRoot)

        let (destination, bytes) = try await workspace.stage(
            source,
            id: UUID(),
            kind: .audio
        ) { _, _ in }

        #expect(bytes == 0)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        let stagedData = try Data(contentsOf: destination)
        #expect(stagedData.isEmpty)
    }

    /// 源文件不存在时检查不留下部分导入目录。
    @Test("Missing source errors do not leave a partial import directory")
    func missingSourceCleansPartialDirectory() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let missing = fixture.root.appending(path: "missing.mov")
        let id = UUID()
        let workspace = ConversionWorkspace(rootURL: fixture.workspaceRoot)
        var didThrow = false

        do {
            _ = try await workspace.stage(missing, id: id, kind: .video) { _, _ in }
        } catch {
            didThrow = true
        }

        let itemDirectory = fixture.workspaceRoot
            .appending(path: "Imports/video/\(id.uuidString)", directoryHint: .isDirectory)
        #expect(didThrow)
        #expect(!FileManager.default.fileExists(atPath: itemDirectory.path))
    }

    /// 检查恢复清单时过滤源文件已消失的记录。
    @Test("Workspace manifests ignore records whose source has disappeared")
    func loadingManifestFiltersMissingSources() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let existing = fixture.root.appending(path: "existing.mov")
        try Data([1]).write(to: existing)
        let workspace = ConversionWorkspace(rootURL: fixture.workspaceRoot)
        let records = [
            PersistedConversionItem(
                id: UUID(),
                sourcePath: existing.path,
                sourceBytes: 1,
                status: .ready,
                outputPath: nil
            ),
            PersistedConversionItem(
                id: UUID(),
                sourcePath: fixture.root.appending(path: "gone.mov").path,
                sourceBytes: 2,
                status: .failed,
                outputPath: nil
            )
        ]

        await workspace.save(records, kind: .video)
        let loaded = await workspace.load(.video)

        #expect(loaded.count == 1)
        #expect(loaded.first?.sourcePath == existing.path)
    }

    /// 检查删除只影响允许的暂存源和输出目录。
    @Test("Deleting a workspace record removes only authorized imported and output files")
    func deletingRecordStaysInsideWorkspaceRoots() async throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let source = fixture.workspaceRoot
            .appending(path: "Imports/image/item", directoryHint: .isDirectory)
            .appending(path: "source.png")
        let outputRoot = fixture.workspaceRoot.appending(path: "Outputs", directoryHint: .isDirectory)
        let output = outputRoot.appending(path: "source.jpg")
        let outside = fixture.root.appending(path: "keep.txt")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        try Data([1]).write(to: source)
        try Data([2]).write(to: output)
        try Data([3]).write(to: outside)

        let record = PersistedConversionItem(
            id: UUID(),
            sourcePath: source.path,
            sourceBytes: 1,
            status: .completed,
            outputPath: output.path
        )
        let workspace = ConversionWorkspace(rootURL: fixture.workspaceRoot)
        let succeeded = await workspace.delete(record, kind: .image, outputRoot: outputRoot)

        #expect(succeeded)
        #expect(!FileManager.default.fileExists(atPath: source.deletingLastPathComponent().path))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}

/// 在异步暂存回调中安全收集进度样本，供测试检查首末值。
private actor ProgressRecorder {
    /// 记录一次回调的已复制字节数和总字节数。
    struct Value: Equatable, Sendable {
        let copied: Int64
        let total: Int64
    }

    private(set) var values: [Value] = []

    /// 将本次进度加入按回调顺序排列的样本列表。
    func append(copied: Int64, total: Int64) {
        values.append(Value(copied: copied, total: total))
    }
}

/// 为每个测试创建独立临时根目录和工作区路径。
private struct WorkspaceFixture {
    let root: URL
    let workspaceRoot: URL

    /// 创建临时根目录；工作区目录由被测对象按需创建。
    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appending(path: "ImageFormatConversionKit-Workspace-\(UUID().uuidString)", directoryHint: .isDirectory)
        workspaceRoot = root.appending(path: "Workspace", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 测试结束时尽力删除临时根目录及其内容。
    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
