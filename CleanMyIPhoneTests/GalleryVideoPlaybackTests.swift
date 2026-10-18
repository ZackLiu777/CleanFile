import Testing
@testable import CleanMyIPhone

@MainActor
private final class PreviewPlaybackSpy: GalleryPlaybackControlling {
    var isPlaying = false
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
}

struct GalleryVideoPlaybackTests {
    @Test @MainActor func selectionImmediatelyPausesPreviousAndRejectsLateCallback() {
        let playback = GalleryVideoPlayback(selectedAssetID: "first")
        let first = PreviewPlaybackSpy(), second = PreviewPlaybackSpy(), late = PreviewPlaybackSpy()
        playback.setEnabled(true)
        playback.activate(first, for: "first")
        #expect(first.isPlaying)
        playback.select("second")
        #expect(!first.isPlaying)
        playback.activate(second, for: "second")
        playback.activate(late, for: "first")
        #expect(second.isPlaying)
        #expect(!late.isPlaying)
        playback.pause(first)
        #expect(second.isPlaying)
        playback.setEnabled(false)
        #expect(!second.isPlaying)
        playback.activate(late, for: "second")
        #expect(!late.isPlaying)
    }

    @Test @MainActor func replacingPlayerPausesOldInstanceAndSwitchingToImageStopsAudio() {
        let playback = GalleryVideoPlayback(selectedAssetID: "video")
        let first = PreviewPlaybackSpy(), replacement = PreviewPlaybackSpy()
        playback.setEnabled(true)
        playback.activate(first, for: "video")
        playback.activate(replacement, for: "video")
        #expect(!first.isPlaying)
        #expect(replacement.isPlaying)
        playback.select("photo")
        #expect(!replacement.isPlaying)
    }
}
