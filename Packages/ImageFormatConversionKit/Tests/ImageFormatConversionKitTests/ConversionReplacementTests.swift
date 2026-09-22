import Foundation
import Testing
@testable import ImageFormatConversionKit

@Suite("Original replacement contracts")
struct ConversionReplacementTests {
    @Test("Only Photos images and videos are eligible for replacement")
    func supportedReplacementKindsExcludeAudio() {
        #expect(ConversionOriginalReplacementService.supportedKinds == [.image, .video])
        #expect(!ConversionOriginalReplacementService.supportedKinds.contains(.audio))
    }

    @Test("Audio replacement is rejected before PhotoKit changes begin")
    func audioReplacementIsRejected() async {
        let candidate = ConversionReplacementCandidate(
            id: UUID(),
            outputURL: URL(fileURLWithPath: "/tmp/compressed-audio.mp3"),
            photoAssetIdentifier: "audio-has-no-photo-asset",
            kind: .audio,
            sourceBytes: 1_000,
            outputBytes: 500
        )

        do {
            _ = try await ConversionOriginalReplacementService.replace([candidate])
            Issue.record("Audio replacement unexpectedly succeeded")
        } catch ConversionOriginalReplacementError.unsupportedOutput {
            // Expected: audio originals cannot be safely deleted through PhotoKit.
        } catch {
            Issue.record("Unexpected replacement error: \(error)")
        }
    }

    @Test("The guide explains the audio replacement limitation")
    func audioReplacementGuideCopyExists() {
        let title = L10n.string("conversion.guide.audio_replace.title")
        let detail = L10n.string("conversion.guide.audio_replace.detail")

        #expect(title != "conversion.guide.audio_replace.title")
        #expect(detail != "conversion.guide.audio_replace.detail")
        #expect(!title.isEmpty)
        #expect(detail.count > 40)
    }
}
