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
    let protectedAssetIDs: Set<String>
    let suggestedDeletionIDs: Set<String>
    let allowsSwipeReview: Bool
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let onDismiss: () -> Void
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityCoordinator

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback: GalleryVideoPlayback
    @State private var isGalleryVisible = false
    @State private var selectedAssetID: String
    @State private var isSwipeReviewPresented = false

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(
        assetIDs: [String],
        initialAssetID: String,
        protectedAssetIDs: Set<String> = [],
        suggestedDeletionIDs: Set<String> = [],
        allowsSwipeReview: Bool = true,
        viewModel: PhotoLibraryViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.assetIDs = assetIDs
        self.initialAssetID = initialAssetID
        self.protectedAssetIDs = protectedAssetIDs
        self.suggestedDeletionIDs = suggestedDeletionIDs
        self.allowsSwipeReview = allowsSwipeReview
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _selectedAssetID = State(initialValue: initialAssetID)
        _playback = StateObject(wrappedValue: GalleryVideoPlayback(selectedAssetID: initialAssetID))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close", systemImage: "xmark") {
                    playback.setEnabled(false)
                    onDismiss()
                }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("media.preview.close")
                Spacer()
                Text(positionText)
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Image(systemName: "xmark").hidden()
            }
            .font(.title3)
            .padding(.horizontal, 20)
            .frame(height: 52)

            TabView(selection: assetSelection) {
                ForEach(assetIDs, id: \.self) { assetID in
                    MediaPreviewPage(
                        assetID: assetID,
                        isActive: assetID == selectedAssetID && isGalleryVisible && scenePhase == .active && !isSwipeReviewPresented,
                        playback: playback,
                        viewModel: viewModel
                    )
                        .tag(assetID)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if assetIDs.count > 1 { thumbnailStrip }

            if allowsSwipeReview,
               viewModel.asset(withIdentifier: selectedAssetID)?.mediaType == .image {
                Button {
                    isSwipeReviewPresented = true
                } label: {
                    Label("Swipe Review", systemImage: "rectangle.stack")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(theme.cardSurface, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .accessibilityIdentifier("media.swipeReview.open")
            }
        }
        .background { AppBackground() }
        .foregroundStyle(theme.textPrimary)
        .preferredColorScheme(themeSettings.effectiveColorScheme)
        .fullScreenCover(isPresented: $isSwipeReviewPresented) {
            MediaSwipeReviewView(
                assetIDs: assetIDs.filter { viewModel.asset(withIdentifier: $0)?.mediaType == .image },
                protectedAssetIDs: protectedAssetIDs,
                suggestedDeletionIDs: suggestedDeletionIDs,
                initialAssetID: selectedAssetID,
                photoLibrary: viewModel,
                onDismiss: { isSwipeReviewPresented = false }
            )
        }
        .onChange(of: scenePhase) { _, _ in updatePlaybackAvailability() }
        .onChange(of: isSwipeReviewPresented) { _, _ in updatePlaybackAvailability() }
        .onAppear {
            isGalleryVisible = true
            updatePlaybackAvailability()
            tabBarVisibility.setHidden(
                true,
                source: "media.preview",
                scope: .media
            )
        }
        .onDisappear {
            isGalleryVisible = false
            playback.setEnabled(false)
            tabBarVisibility.setHidden(
                false,
                source: "media.preview",
                scope: .media
            )
        }
    }

    private var assetSelection: Binding<String> {
        Binding(get: { selectedAssetID }, set: { identifier in
            // Pause synchronously at selection, without waiting for page onDisappear.
            playback.select(identifier)
            selectedAssetID = identifier
        })
    }

    private func updatePlaybackAvailability() {
        playback.setEnabled(isGalleryVisible && scenePhase == .active && !isSwipeReviewPresented)
    }

    private var positionText: String {
        guard let index = assetIDs.firstIndex(of: selectedAssetID) else { return "" }
        return "\(index + 1) / \(assetIDs.count)"
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(assetIDs, id: \.self) { identifier in
                        Button { assetSelection.wrappedValue = identifier } label: {
                            GalleryThumbnail(asset: viewModel.asset(withIdentifier: identifier), viewModel: viewModel)
                                .frame(width: 48, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(selectedAssetID == identifier ? theme.accentPrimary : .clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(identifier)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedAssetID) { _, identifier in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(identifier, anchor: .center)
                }
            }
        }
        .frame(height: 64)
        .accessibilityIdentifier("media.preview.thumbnails")
    }
}

private struct GalleryThumbnail: View {
    let asset: PHAsset?
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.appTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            theme.cardSurface
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(theme.textTertiary)
            }
        }
        .frame(width: 48, height: 58)
        .clipped()
        .onAppear {
            guard let asset else { return }
            image = viewModel.cachedThumbnail(for: asset.localIdentifier)
            requestID = viewModel.requestThumbnail(
                for: asset,
                targetSize: CGSize(width: 48 * displayScale, height: 58 * displayScale)
            ) { loadedImage in
                if let loadedImage { image = loadedImage }
            }
        }
        .onDisappear {
            if let requestID { viewModel.cancelThumbnail(requestID) }
            requestID = nil
        }
    }
}

/// 定义 `MediaPreviewPage` 的值语义数据与相关行为。
private struct MediaPreviewPage: View {
    let assetID: String
    let isActive: Bool
    let playback: GalleryVideoPlayback
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        if let asset = viewModel.asset(withIdentifier: assetID) {
            if asset.mediaType == .video {
                VideoAssetPreview(asset: asset, isActive: isActive, playback: playback, viewModel: viewModel)
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
        .foregroundStyle(theme.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 定义 `ZoomablePhotoPreview` 的值语义数据与相关行为。
private struct ZoomablePhotoPreview: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.appTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var state: MediaPreviewState = .loading
    @State private var requestID: PHImageRequestID?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    NativeZoomableImage(image: image)
                } else if state == .loading {
                    ProgressView("Loading…")
                        .tint(theme.accentPrimary)
                        .foregroundStyle(theme.textPrimary)
                } else {
                    unavailableView
                }
            }
            .clipped()
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

    private var unavailableView: some View {
        Label("Photo Unavailable", systemImage: "icloud.slash")
            .foregroundStyle(theme.textPrimary)
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

/// 使用系统 UIScrollView 的原生缩放管线，避免 SwiftUI 分页与自定义手势竞争。
private struct NativeZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.zoomContentView.backgroundColor = .clear
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        scrollView.zoomContentView.addSubview(imageView)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        scrollView.onLayout = { [weak coordinator = context.coordinator] bounds in
            coordinator?.layoutContent(in: bounds)
        }

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        }
        context.coordinator.layoutContent(in: scrollView.bounds)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        private var laidOutSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.zoomContentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerZoomedContent(in: scrollView)
        }

        func layoutContent(in bounds: CGRect) {
            guard bounds.width > 0, bounds.height > 0,
                  let scrollView,
                  let imageView,
                  let contentView = (scrollView as? ZoomScrollView)?.zoomContentView
            else { return }
            guard bounds.size != laidOutSize else { return }

            // 尺寸变化时先恢复 1x，避免修改已带 transform 的 zoom view frame。
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
            laidOutSize = bounds.size
            contentView.frame = CGRect(origin: .zero, size: bounds.size)
            imageView.frame = contentView.bounds
            scrollView.contentSize = bounds.size
            centerZoomedContent(in: scrollView)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let targetScale = min(2.5, scrollView.maximumZoomScale)
            let point = recognizer.location(in: imageView)
            let size = CGSize(
                width: scrollView.bounds.width / targetScale,
                height: scrollView.bounds.height / targetScale
            )
            scrollView.zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                animated: true
            )
        }

        private func centerZoomedContent(in scrollView: UIScrollView) {
            let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: vertical,
                left: horizontal,
                bottom: vertical,
                right: horizontal
            )
        }
    }
}

/// 在尺寸变化时同步原生缩放内容，避免旋转或导航栏布局后使用过期 bounds。
private final class ZoomScrollView: UIScrollView {
    let zoomContentView = UIView()
    var onLayout: ((CGRect) -> Void)?
    private var previousBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(zoomContentView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousBoundsSize else { return }
        previousBoundsSize = bounds.size
        onLayout?(bounds)
    }
}

/// 定义 `VideoAssetPreview` 的值语义数据与相关行为。
private struct VideoAssetPreview: View {
    let asset: PHAsset
    let isActive: Bool
    let playback: GalleryVideoPlayback
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.appTheme) private var theme
    @State private var player: AVPlayer?
    @State private var state: MediaPreviewState = .loading
    @State private var requestID: PHImageRequestID?
    @State private var requestGeneration: UUID?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: isActive ? player : nil)
                    .onAppear { synchronizePlayback() }
            } else if state == .loading {
                ProgressView("Loading Video…")
                    .tint(theme.accentPrimary)
                    .foregroundStyle(theme.textPrimary)
            } else {
                Label("Video Unavailable", systemImage: "icloud.slash")
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .task(id: asset.localIdentifier, loadPlayer)
        .onChange(of: isActive) { _, _ in synchronizePlayback() }
        .onDisappear {
            requestGeneration = nil
            playback.pause(player)
            if let requestID { viewModel.cancelThumbnail(requestID) }
            requestID = nil
        }
    }

    /// 加载 `loadPlayer` 所需的数据，并将结果转换为当前层可消费的状态。
    private func loadPlayer() async {
        guard player == nil else {
            synchronizePlayback()
            return
        }
        state = .loading
        let generation = UUID()
        requestGeneration = generation
        requestID = viewModel.requestPlayerItem(for: asset) { item in
            guard requestGeneration == generation else { return }
            guard let item else {
                state = .unavailable
                return
            }
            let loadedPlayer = AVPlayer(playerItem: item)
            player = loadedPlayer
            state = .ready
            // The callback can outlive the page's captured isActive value.
            // Consult the shared current selection rather than that old value.
            playback.activate(loadedPlayer, for: asset.localIdentifier)
        }
    }
    private func synchronizePlayback() {
        guard let player else { return }
        if isActive {
            playback.activate(player, for: asset.localIdentifier)
        } else {
            playback.pause(player)
        }
    }

}

/// 定义 `LivePhotoAssetPreview` 的值语义数据与相关行为。
private struct LivePhotoAssetPreview: View {
    let asset: PHAsset
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.appTheme) private var theme
    @State private var livePhoto: PHLivePhoto?
    @State private var state: MediaPreviewState = .loading
    @State private var requestID: PHImageRequestID?
    @State private var playbackTrigger = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
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
                        .tint(theme.accentPrimary)
                        .foregroundStyle(theme.textPrimary)
                } else {
                    Label("Live Photo Unavailable", systemImage: "icloud.slash")
                        .foregroundStyle(theme.textPrimary)
                }

                if livePhoto != nil {
                    VStack {
                        Spacer()
                        Label("Press and hold to play", systemImage: "livephoto")
                            .appTypeface(.caption.weight(.semibold), size: 12, relativeTo: .caption, weight: .semibold)
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
