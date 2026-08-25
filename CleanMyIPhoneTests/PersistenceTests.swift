import Foundation
import Testing
@testable import CleanMyIPhone

@Suite("Persisted state contracts")
struct PersistenceTests {
    @Test("Media snapshot preserves complete analysis state")
    func mediaSnapshotRoundTrip() throws {
        let result = MediaClassificationResult(
            similarImageGroups: [
                SimilarImageGroup(
                    id: "group",
                    items: [
                        SimilarImageItem(id: "one", pixelWidth: 10, pixelHeight: 20, creationDate: Date(timeIntervalSince1970: 10)),
                        SimilarImageItem(id: "two", pixelWidth: 30, pixelHeight: 40, creationDate: nil)
                    ],
                    suggestedKeeperID: "two"
                )
            ],
            classifiedVideos: [
                ClassifiedVideo(
                    id: "video",
                    duration: 42,
                    pixelWidth: 3_840,
                    pixelHeight: 2_160,
                    categories: [.fourK, .screenRecording]
                )
            ],
            screenshotIDs: ["shot"],
            livePhotoIDs: ["live"],
            skippedImageCount: 2
        )
        let snapshot = MediaStateSnapshot(result: result, isPartial: true)

        let decoded = try JSONDecoder().decode(
            MediaStateSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.result == result)
        #expect(decoded.isPartial)
    }

    @Test("File snapshot preserves relative paths and unknown sizes")
    func fileSnapshotRoundTrip() throws {
        let file = ScannedFile(
            url: URL(fileURLWithPath: "/provider/transient-id"),
            name: "cloud.pdf",
            relativePathComponents: ["Documents", "cloud.pdf"],
            category: .pdf,
            byteCount: 0,
            hasKnownByteCount: false,
            creationDate: Date(timeIntervalSince1970: 20),
            modificationDate: Date(timeIntervalSince1970: 30)
        )
        let snapshot = FileStateSnapshot(
            directoryBookmark: Data([1, 2, 3]),
            selectedDirectoryName: "Documents",
            files: [file],
            skippedFileCount: 4
        )

        let decoded = try JSONDecoder().decode(
            FileStateSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded.directoryBookmark == Data([1, 2, 3]))
        #expect(decoded.selectedDirectoryName == "Documents")
        #expect(decoded.files == [file])
        #expect(decoded.skippedFileCount == 4)
    }

    @Test("All file categories retain stable persisted raw values")
    func fileCategoryCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(FileCategory.allCases)
        let decoded = try JSONDecoder().decode([FileCategory].self, from: encoded)

        #expect(decoded == FileCategory.allCases)
    }

    @Test("All video categories retain stable persisted raw values")
    func videoCategoryCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(VideoCategory.allCases)
        let decoded = try JSONDecoder().decode([VideoCategory].self, from: encoded)

        #expect(decoded == VideoCategory.allCases)
    }

    @Test("Corrupted media snapshot is rejected")
    func corruptedMediaSnapshotIsRejected() {
        let malformed = Data("{\"result\":false}".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MediaStateSnapshot.self, from: malformed)
        }
    }

    @Test("Corrupted file snapshot is rejected")
    func corruptedFileSnapshotIsRejected() {
        let malformed = Data("not-json".utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FileStateSnapshot.self, from: malformed)
        }
    }
}

@MainActor
@Suite("Theme persistence")
struct ThemePersistenceTests {
    @Test("Theme defaults to light when no value exists")
    func themeDefaultsToLight() {
        let defaults = isolatedDefaults()

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .light)
    }

    @Test("Theme restores a persisted dark value")
    func themeRestoresPersistedDarkValue() {
        let defaults = isolatedDefaults()
        defaults.set(AppAppearance.dark.rawValue, forKey: "appAppearance")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .dark)
    }

    @Test("Invalid persisted theme safely falls back to light")
    func invalidThemeFallsBackToLight() {
        let defaults = isolatedDefaults()
        defaults.set("unsupported", forKey: "appAppearance")

        let settings = ThemeSettings(userDefaults: defaults)

        #expect(settings.appearance == .light)
    }

    @Test("Changing theme persists immediately")
    func changingThemePersistsImmediately() {
        let defaults = isolatedDefaults()
        let settings = ThemeSettings(userDefaults: defaults)

        settings.appearance = .dark

        #expect(defaults.string(forKey: "appAppearance") == AppAppearance.dark.rawValue)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "CleanMyIPhoneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
