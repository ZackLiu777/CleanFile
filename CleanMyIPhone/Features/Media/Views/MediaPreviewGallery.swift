// 图片、视频和实况照片的全屏预览。
// 按当前页面协调资源请求、缩放和视频播放；视图切换时停止不再需要的工作。
// 预览页按资源类型请求图片、视频或实况照片，并提供缩略图导航和审阅入口。
// 图片缩放使用原生滚动视图；视频由共享播放协调器限制为当前选中页面。

//
//  MediaPreviewGallery.swift
//  CleanMyIPhone
//


import AVKit
import Photos
import PhotosUI
import SwiftUI

/// 区分媒体预览加载中、可用和不可用状态。
private enum MediaPreviewState: Equatable {
    case loading
    case ready
    case unavailable
}

/// 协调全屏页面选择、资源预览与播放，并支持返回和选择操作。
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

    /// 建立预览资源清单、初始页面、审阅配置和关闭回调。
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

    /// 按当前页面和展示状态同步视频播放权限，避免相邻预加载页面同时播放。
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

/// 展示底部媒体缩略图，随视图生命周期管理图片请求。
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

/// 根据资源类型选择图片、视频或实况照片的预览方式。
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

/// 请求并展示可缩放的照片预览，视图生命周期结束时取消请求。
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

    /// 取消旧请求后按显示尺寸和屏幕倍率请求图片，并更新加载状态。
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

    /// 取消当前图片请求，防止页面切换后继续接收不需要的预览。
    private func cancelRequest() {
        if let requestID { viewModel.cancelThumbnail(requestID) }
        requestID = nil
    }
}

/// 使用系统 UIScrollView 的原生缩放管线，避免 SwiftUI 分页与自定义手势竞争。
private struct NativeZoomableImage: UIViewRepresentable {
    let image: UIImage

    /// 创建负责滚动缩放、布局与双击手势的协调对象。
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// 配置原生缩放容器、图像视图和双击手势，并连接布局回调。
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

    /// 图片改变时重置缩放，并依据当前容器尺寸更新布局。
    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        }
        context.coordinator.layoutContent(in: scrollView.bounds)
    }

    /// 协调原生滚动视图的缩放目标、内容居中和尺寸变化。
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        private var laidOutSize: CGSize = .zero

        /// 指定承载图像的内容视图作为原生缩放目标。
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.zoomContentView
        }

        /// 缩放过程中重新计算内容边距，使较小内容保持居中。
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerZoomedContent(in: scrollView)
        }

        /// 仅在尺寸变化时恢复初始缩放并重设内容尺寸，避免修改变换后的 frame。
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

        /// 双击已放大图片时复位；否则以触点为中心放大到目标比例。
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

        /// 以对称内边距居中小于视口的缩放内容。
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

    /// 以代码创建滚动容器，并安装可缩放的内容视图。
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(zoomContentView)
    }

    /// 该滚动容器仅通过代码创建，不支持从归档解码。
    required init?(coder: NSCoder) {
        nil
    }

    /// 只在边界尺寸变化时通知协调器重新布局内容。
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousBoundsSize else { return }
        previousBoundsSize = bounds.size
        onLayout?(bounds)
    }
}

/// 获取视频播放资源，并依据当前页面状态同步播放。
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

    /// 异步获取视频播放资源，并与当前预览页的生命周期协调。
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
    /// 依据当前页面是否激活，向共享协调器请求播放或暂停。
    private func synchronizePlayback() {
        guard let player else { return }
        if isActive {
            playback.activate(player, for: asset.localIdentifier)
        } else {
            playback.pause(player)
        }
    }

}

/// 请求并展示实况照片资源，依赖系统视图完成播放。
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

    /// 请求适合当前显示尺寸的实况照片，并更新预览状态。
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

/// 将系统实况照片视图包装给 SwiftUI，并根据播放触发值启动播放。
private struct LivePhotoPlayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playbackTrigger: Int

    /// 创建协调器以记录上一次已处理的播放触发值。
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 创建用于展示实况照片的系统视图。
    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        return view
    }

    /// 更新实况照片，并只在播放触发值变化时重新播放。
    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        view.livePhoto = livePhoto
        guard context.coordinator.lastPlaybackTrigger != playbackTrigger else { return }
        context.coordinator.lastPlaybackTrigger = playbackTrigger
        view.startPlayback(with: .full)
    }

    /// 记录已处理的触发值，避免普通视图更新重复启动播放。
    final class Coordinator {
        var lastPlaybackTrigger = -1
    }
}
