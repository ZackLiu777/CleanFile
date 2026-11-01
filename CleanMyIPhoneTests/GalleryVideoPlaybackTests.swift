//
//  图库视频播放协调
//
//  覆盖资源切换时旧播放器暂停及过期回调的处理。
//  使用播放控制替身检查协调行为，不需要真实媒体播放。
//  同一资源替换播放器、切换到图片及禁用播放时，旧播放器都应暂停。
//  过期请求即使随后返回，也不能抢占当前选中的资源。
//

import Testing
@testable import CleanMyIPhone

/// 记录播放与暂停状态，替代真实播放器供测试断言。
@MainActor
private final class PreviewPlaybackSpy: GalleryPlaybackControlling {
    var isPlaying = false
    /// 只记录播放状态，不启动真实媒体播放器。
    func play() { isPlaying = true }
    /// 记录暂停状态，供测试检查旧播放器是否停止。
    func pause() { isPlaying = false }
}

/// 验证切换资源时播放协调器不会继续播放旧内容。
struct GalleryVideoPlaybackTests {
    /// 切换选中资源后立即暂停旧播放，并拒绝迟到的旧请求结果。
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

    /// 替换播放器和切换到图片时均停止旧音频。
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
