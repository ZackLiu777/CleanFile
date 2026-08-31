import Foundation
import Testing
@testable import ImageFormatConversionKit

@Suite("Conversion workspace edge cases")
struct ConversionWorkspaceEdgeCaseTests {
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

private actor ProgressRecorder {
    struct Value: Equatable, Sendable {
        let copied: Int64
        let total: Int64
    }

    private(set) var values: [Value] = []

    func append(copied: Int64, total: Int64) {
        values.append(Value(copied: copied, total: total))
    }
}

private struct WorkspaceFixture {
    let root: URL
    let workspaceRoot: URL

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appending(path: "ImageFormatConversionKit-Workspace-\(UUID().uuidString)", directoryHint: .isDirectory)
        workspaceRoot = root.appending(path: "Workspace", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
