// 媒体预览中的视频播放协调。
// 只有当前选中且允许播放的页面持有播放机会；页面切换时及时暂停其他播放器。
// 全屏预览页将播放器注册到共享协调器，由资源标识决定哪一页可以播放。
// 邻近页面即使仍由 SwiftUI 保留，也会在选择切换或播放禁用时暂停。

import AVFoundation
import Combine

/// 预览播放协调所需的最小播放接口，允许协调器管理播放器而不依赖具体视图。
@MainActor
protocol GalleryPlaybackControlling: AnyObject {
    /// 开始播放当前资源。
    func play()
    /// 暂停播放当前资源。
    func pause()
}

extension AVPlayer: GalleryPlaybackControlling {}

/// The selected page owns playback even while SwiftUI keeps neighboring pages alive.
@MainActor
final class GalleryVideoPlayback: ObservableObject {
    private var selectedAssetID: String
    private var isEnabled = false
    private weak var currentPlayer: (any GalleryPlaybackControlling)?

    /// 以当前预览资源作为唯一允许获得播放机会的页面。
    init(selectedAssetID: String) { self.selectedAssetID = selectedAssetID }

    /// 切换选中资源前暂停当前播放器，避免旧页面继续播放。
    func select(_ assetID: String) {
        guard selectedAssetID != assetID else { return }
        pauseCurrent()
        selectedAssetID = assetID
    }

    /// 更新全局播放许可；禁用时立即暂停当前播放器。
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { pauseCurrent() }
    }

    /// 仅允许当前选中且播放已启用的资源启动，并暂停先前播放器。
    func activate(_ player: any GalleryPlaybackControlling, for assetID: String) {
        guard isEnabled, selectedAssetID == assetID else {
            player.pause()
            return
        }
        if currentPlayer !== player { pauseCurrent() }
        currentPlayer = player
        player.play()
    }

    /// 暂停指定播放器；若它是当前播放器则释放协调器引用。
    func pause(_ player: (any GalleryPlaybackControlling)?) {
        player?.pause()
        if let player, currentPlayer === player { currentPlayer = nil }
    }

    /// 暂停并释放当前播放器引用。
    private func pauseCurrent() {
        currentPlayer?.pause()
        currentPlayer = nil
    }
}
