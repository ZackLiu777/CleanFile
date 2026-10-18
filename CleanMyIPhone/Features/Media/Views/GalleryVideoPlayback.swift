import AVFoundation
import Combine

@MainActor
protocol GalleryPlaybackControlling: AnyObject {
    func play()
    func pause()
}

extension AVPlayer: GalleryPlaybackControlling {}

/// The selected page owns playback even while SwiftUI keeps neighboring pages alive.
@MainActor
final class GalleryVideoPlayback: ObservableObject {
    private var selectedAssetID: String
    private var isEnabled = false
    private weak var currentPlayer: (any GalleryPlaybackControlling)?

    init(selectedAssetID: String) { self.selectedAssetID = selectedAssetID }

    func select(_ assetID: String) {
        guard selectedAssetID != assetID else { return }
        pauseCurrent()
        selectedAssetID = assetID
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { pauseCurrent() }
    }

    func activate(_ player: any GalleryPlaybackControlling, for assetID: String) {
        guard isEnabled, selectedAssetID == assetID else {
            player.pause()
            return
        }
        if currentPlayer !== player { pauseCurrent() }
        currentPlayer = player
        player.play()
    }

    func pause(_ player: (any GalleryPlaybackControlling)?) {
        player?.pause()
        if let player, currentPlayer === player { currentPlayer = nil }
    }

    private func pauseCurrent() {
        currentPlayer?.pause()
        currentPlayer = nil
    }
}
