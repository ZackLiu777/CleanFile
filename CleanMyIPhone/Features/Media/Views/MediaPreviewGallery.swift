//
//  MediaPreviewGallery.swift
//  CleanMyIPhone
//

//
//  文件职责：集中定义 MediaPreviewGallery 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import AVKit
import Photos
import PhotosUI
import SwiftUI

/// 定义 `MediaPreviewState` 使用的有限状态或选项集合。
private enum MediaPreviewState: Equatable {
    case loading
    case ready
    case unavailable
}

/// 定义 `MediaPreviewGallery` 的值语义数据与相关行为。
struct MediaPreviewGallery: View {
    let assetIDs: [String]
    let initialAssetID: String
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let onDismiss: () -> Void

    @State private var selectedAssetID: String

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(
        assetIDs: [String],
        initialAssetID: String,
        viewModel: PhotoLibraryViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.assetIDs = assetIDs
        self.initialAssetID = initialAssetID
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _selectedAssetID = State(initialValue: initialAssetID)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedAssetID) {
                ForEach(assetIDs, id: \.self) { assetID in
                    MediaPreviewPage(assetID: assetID, viewModel: viewModel)
                        .tag(assetID)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .navigationTitle(positionText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black.opacity(0.72), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done", action: onDismiss)
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var positionText: String {
        guard let index = assetIDs.firstIndex(of: selectedAssetID) else { return "" }
        return "\(index + 1) / \(assetIDs.count)"
    }
}

/// 定义 `MediaPreviewPage` 的值语义数据与相关行为。
private struct MediaPreviewPage: View {
    let assetID: String
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        if let asset = viewModel.asset(withIdentifier: assetID) {
            if asset.mediaType == .video {
                VideoAssetPreview(asset: asset, viewModel: viewModel)
            } else if asset.mediaSubtypes.contains(.photoLive) {
                LivePhotoAssetPreview(asset: asset, viewModel: viewModel)
            } else {
                ZoomablePhotoPreview(asset: asset, viewModel: viewModel)
            }
        } else {
            previewUnavailable
        }
    }

    private var previewUnavailable: some View {
        ContentUnavailableView(
            "Media Unavailable",
            systemImage: "icloud.slash",
            description: Text("This item could not be loaded from the photo library.")
        )
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

/// 定义 `ZoomablePhotoPreview` 的值语义数据与相关行为。
private struct ZoomablePhotoPreview: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var state: MediaPreviewState = .loading
    @State private var requestID: PHImageRequestID?
    @State private var baseScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(effectiveScale)
                        .offset(effectiveOffset)
                        .gesture(magnificationGesture)
                        .simultaneousGesture(dragGesture)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                baseScale = baseScale > 1 ? 1 : 2.5
                                gestureScale = 1
                                if baseScale == 1 {
                                    baseOffset = .zero
                                    gestureOffset = .zero
                                }
                            }
                        }
                } else if state == .loading {
                    ProgressView("Loading…")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else {
                    unavailableView
                }
            }
            .task(id: asset.localIdentifier) {
                requestImage(for: proxy.size)
            }
        }
        .onDisappear(perform: cancelRequest)
        .onAppear {
            if image == nil {
                image = viewModel.cachedThumbnail(for: asset.localIdentifier)
            }
        }
    }

    private var effectiveScale: CGFloat {
        min(max(baseScale * gestureScale, 1), 5)
    }

    private var effectiveOffset: CGSize {
        guard effectiveScale > 1 else { return .zero }
        return CGSize(
            width: baseOffset.width + gestureOffset.width,
            height: baseOffset.height + gestureOffset.height
        )
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { gestureScale = $0.magnification }
            .onEnded {
                baseScale = min(max(baseScale * $0.magnification, 1), 5)
                gestureScale = 1
                if baseScale == 1 { baseOffset = .zero }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard effectiveScale > 1 else { return }
                gestureOffset = value.translation
            }
            .onEnded { value in
                guard effectiveScale > 1 else { return }
                baseOffset.width += value.translation.width
                baseOffset.height += value.translation.height
                gestureOffset = .zero
            }
    }

    private var unavailableView: some View {
        Label("Photo Unavailable", systemImage: "icloud.slash")
            .foregroundStyle(.white)
    }

    /// 封装 `requestImage` 对应的局部行为，供当前类型在统一入口下复用。
    private func requestImage(for size: CGSize) {
        cancelRequest()
        state = .loading
        requestID = viewModel.requestPreviewImage(
            for: asset,
            targetSize: CGSize(
                width: max(size.width, 1) * displayScale,
                height: max(size.height, 1) * displayScale
            )
        ) { loadedImage in
            image = loadedImage
            state = loadedImage == nil ? .unavailable : .ready
        }
    }

    /// 取消 `cancelRequest` 对应的进行中任务，并收敛到可继续操作的状态。
    private func cancelRequest() {
        if let requestID { viewModel.cancelThumbnail(requestID) }
        requestID = nil
    }
}

/// 定义 `VideoAssetPreview` 的值语义数据与相关行为。
private struct VideoAssetPreview: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var player: AVPlayer?
    @State private var state: MediaPreviewState = .loading
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else if state == .loading {
                ProgressView("Loading Video…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else {
                Label("Video Unavailable", systemImage: "icloud.slash")
                    .foregroundStyle(.white)
            }
        }
        .task(id: asset.localIdentifier, loadPlayer)
        .onDisappear {
            player?.pause()
            if let requestID { viewModel.cancelThumbnail(requestID) }
            requestID = nil
        }
    }

    /// 加载 `loadPlayer` 所需的数据，并将结果转换为当前层可消费的状态。
    private func loadPlayer() async {
        state = .loading
        requestID = viewModel.requestPlayerItem(for: asset) { item in
            guard let item else {
                state = .unavailable
                return
            }
            player = AVPlayer(playerItem: item)
            state = .ready
            player?.play()
        }
    }
}

/// 定义 `LivePhotoAssetPreview` 的值语义数据与相关行为。
private struct LivePhotoAssetPreview: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var livePhoto: PHLivePhoto?
    @State private var state: MediaPreviewState = .loading
    @State private var requestID: PHImageRequestID?
    @State private var playbackTrigger = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let livePhoto {
                    LivePhotoPlayerView(
                        livePhoto: livePhoto,
                        playbackTrigger: playbackTrigger
                    )
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.15) {
                        playbackTrigger += 1
                    }
                } else if state == .loading {
                    ProgressView("Loading Live Photo…")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else {
                    Label("Live Photo Unavailable", systemImage: "icloud.slash")
                        .foregroundStyle(.white)
                }

                if livePhoto != nil {
                    VStack {
                        Spacer()
                        Label("Press and hold to play", systemImage: "livephoto")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 24)
                    }
                }
            }
            .task(id: asset.localIdentifier) {
                requestLivePhoto(for: proxy.size)
            }
        }
        .onDisappear {
            if let requestID { viewModel.cancelThumbnail(requestID) }
            requestID = nil
        }
    }

    /// 封装 `requestLivePhoto` 对应的局部行为，供当前类型在统一入口下复用。
    private func requestLivePhoto(for size: CGSize) {
        state = .loading
        requestID = viewModel.requestLivePhoto(
            for: asset,
            targetSize: CGSize(width: max(size.width, 1), height: max(size.height, 1))
        ) { loadedLivePhoto in
            livePhoto = loadedLivePhoto
            state = loadedLivePhoto == nil ? .unavailable : .ready
            if loadedLivePhoto != nil { playbackTrigger += 1 }
        }
    }
}

/// 定义 `LivePhotoPlayerView` 的值语义数据与相关行为。
private struct LivePhotoPlayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playbackTrigger: Int

    /// 创建 `makeCoordinator` 所需的值或资源，统一封装构造细节。
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 创建 `makeUIView` 所需的值或资源，统一封装构造细节。
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    /// 更新 `updateUIView` 对应的数据，使界面状态与底层结果保持一致。
    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        view.livePhoto = livePhoto
        guard context.coordinator.lastPlaybackTrigger != playbackTrigger else { return }
        context.coordinator.lastPlaybackTrigger = playbackTrigger
        view.startPlayback(with: .full)
    }

    /// 封装 `Coordinator` 的引用语义、状态与业务行为。
    final class Coordinator {
        var lastPlaybackTrigger = -1
    }
}
