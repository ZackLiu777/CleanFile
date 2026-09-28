import Photos
import SwiftUI

/// Optional, deliberate review flow. Swipes update a local selection, not the photo library.
struct MediaSwipeReviewView: View {
    private enum Confirmation {
        case discard
        case delete
    }

    @ObservedObject var photoLibrary: PhotoLibraryViewModel
    let suggestedDeletionIDs: Set<String>
    let onDismiss: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityCoordinator

    @State private var session: MediaSwipeReviewSession
    @State private var previewIsReady = false
    @State private var dragX: CGFloat = 0
    @State private var isShowingFullPreview = false
    @State private var isShowingSummary = false
    @State private var confirmation: Confirmation?
    @State private var deletionError: String?
    @State private var deletedCount: Int?
    @State private var decisionFeedbackCount = 0

    init(
        assetIDs: [String],
        protectedAssetIDs: Set<String>,
        suggestedDeletionIDs: Set<String> = [],
        initialAssetID: String? = nil,
        photoLibrary: PhotoLibraryViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.photoLibrary = photoLibrary
        self.suggestedDeletionIDs = suggestedDeletionIDs
        self.onDismiss = onDismiss
        _session = State(initialValue: MediaSwipeReviewSession(
            assetIDs: assetIDs,
            protectedAssetIDs: protectedAssetIDs,
            initialAssetID: initialAssetID
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let deletedCount {
                    completionView(deletedCount: deletedCount)
                } else if isShowingSummary || session.currentAssetID == nil {
                    summaryView
                } else {
                    activeReview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppBackground() }
            .foregroundStyle(theme.textPrimary)
            .navigationTitle("Swipe Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { close() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if deletedCount == nil && session.canUndo {
                        Button("Undo", systemImage: "arrow.uturn.backward") {
                            session.undo()
                            previewIsReady = false
                            isShowingSummary = false
                        }
                        .accessibilityIdentifier("media.swipeReview.undo")
                    }
                }
            }
        }
        .preferredColorScheme(themeSettings.effectiveColorScheme)
        .sensoryFeedback(.selection, trigger: decisionFeedbackCount)
        .fullScreenCover(isPresented: $isShowingFullPreview) {
            if let assetID = session.currentAssetID {
                MediaPreviewGallery(
                    assetIDs: [assetID],
                    initialAssetID: assetID,
                    allowsSwipeReview: false,
                    viewModel: photoLibrary,
                    onDismiss: { isShowingFullPreview = false }
                )
            }
        }
        .alert(
            confirmation == .discard ? "Discard this review?" : "Delete marked media?",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { confirmation = nil }
            if confirmation == .discard {
                Button("Discard", role: .destructive, action: onDismiss)
            } else {
                Button("Delete", role: .destructive) { deleteMarkedMedia() }
            }
        } message: {
            if confirmation == .discard {
                Text("Your choices have not changed your photo library.")
            } else {
                Text("Photos will ask you to confirm. Deleted items move to Recently Deleted.")
            }
        }
        .onAppear {
            tabBarVisibility.setHidden(true, source: "media.swipeReview", scope: .media)
        }
        .onDisappear {
            tabBarVisibility.setHidden(false, source: "media.swipeReview", scope: .media)
        }
    }

    private var activeReview: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(session.currentIndex + 1) / \(session.assetIDs.count)")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Spacer()
                Text(String.localizedStringWithFormat(
                    AppL10n.string("%lld marked for deletion"),
                    Int64(session.pendingDeletionIDs.count)
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(session.pendingDeletionIDs.isEmpty ? theme.textSecondary : theme.negativeRed)
            }
            .padding(.horizontal, 20)

            if !suggestedDeletionIDs.isEmpty {
                Button {
                    let markedCount = session.markSuggestedDeletions(suggestedDeletionIDs)
                    guard markedCount > 0 else { return }
                    decisionFeedbackCount += 1
                    isShowingSummary = true
                } label: {
                    Label("Select Similar Photos", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!suggestedDeletionIDs.contains(where: {
                    session.decisions[$0] == nil && !session.protectedAssetIDs.contains($0)
                }))
                .padding(.horizontal, 16)
                .accessibilityIdentifier("media.swipeReview.selectSimilar")
            }

            if let assetID = session.currentAssetID,
               let asset = photoLibrary.asset(withIdentifier: assetID) {
                reviewCard(asset: asset)
                    .accessibilityIdentifier("media.swipeReview.card")

                thumbnailStrip

                Button("Open Full Preview", systemImage: "arrow.up.left.and.arrow.down.right") {
                    isShowingFullPreview = true
                }
                .font(.subheadline)
                .accessibilityIdentifier("media.swipeReview.fullPreview")

                if session.protectedAssetIDs.contains(assetID) {
                    Label("Suggested photo to keep", systemImage: "shield.checkered")
                        .font(.caption)
                        .foregroundStyle(theme.warningOrange)
                } else {
                    Text("Swipe left to mark for deletion · right to keep")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }

                HStack(spacing: 12) {
                    Button {
                        decide(.delete)
                    } label: {
                        Label("Mark for Deletion", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.negativeRed)
                    .disabled(!previewIsReady || session.protectedAssetIDs.contains(assetID))
                    .accessibilityIdentifier("media.swipeReview.markDelete")

                    Button {
                        decide(.keep)
                    } label: {
                        Label("Keep", systemImage: "heart")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.positiveGreen)
                    .disabled(!previewIsReady)
                    .accessibilityIdentifier("media.swipeReview.keep")
                }
                .padding(.horizontal, 16)
            } else {
                ContentUnavailableView("Media Unavailable", systemImage: "icloud.slash")
                    .frame(maxHeight: .infinity)
            }

            if !previewIsReady {
                Button("Skip") { skip() }
                    .font(.caption)
                    .padding(.bottom, 2)
            }

            Button {
                isShowingSummary = true
            } label: {
                HStack {
                    Image(systemName: "checklist")
                    Text("Review Selection")
                    Spacer()
                    Text("\(session.pendingDeletionIDs.count)")
                    Image(systemName: "chevron.right")
                }
                .font(.headline)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("media.swipeReview.reviewSelection")
        }
        .padding(.vertical, 12)
    }

    private func reviewCard(asset: PHAsset) -> some View {
        ReviewAssetCard(asset: asset, photoLibrary: photoLibrary) { assetID, isReady in
            guard session.currentAssetID == assetID else { return }
            previewIsReady = isReady
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: dragX < 0 ? .topTrailing : .topLeading) {
            if abs(dragX) > 30 {
                Label(dragX < 0 ? "Mark for Deletion" : "Keep", systemImage: dragX < 0 ? "trash" : "heart")
                    .font(.headline)
                    .padding(12)
                    .background(dragX < 0 ? theme.negativeRed : theme.positiveGreen, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(18)
            }
        }
        .offset(x: dragX)
        .rotationEffect(.degrees(Double(dragX / 30)))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard previewIsReady,
                          abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                    dragX = session.protectedAssetIDs.contains(asset.localIdentifier)
                        ? max(0, value.translation.width) : value.translation.width
                }
                .onEnded { value in
                    let horizontal = value.translation.width
                    if previewIsReady, abs(horizontal) > 110,
                       (horizontal > 0 || !session.protectedAssetIDs.contains(asset.localIdentifier)),
                       abs(horizontal) > abs(value.translation.height) * 1.2 {
                        decide(horizontal < 0 ? .delete : .keep)
                    }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { dragX = 0 }
                }
        )
    }

    private func decide(_ decision: MediaSwipeReviewSession.Decision) {
        guard session.decide(decision) else { return }
        decisionFeedbackCount += 1
        previewIsReady = false
        dragX = 0
        isShowingSummary = session.isComplete
    }

    private func skip() {
        session.skip()
        previewIsReady = false
        dragX = 0
        isShowingSummary = session.isComplete
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(session.assetIDs.indices, id: \.self) { index in
                        let identifier = session.assetIDs[index]
                        Button {
                            guard session.selectAsset(at: index) else { return }
                            previewIsReady = false
                            dragX = 0
                        } label: {
                            ReviewThumbnail(asset: photoLibrary.asset(withIdentifier: identifier), photoLibrary: photoLibrary)
                                .frame(width: 54, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(session.currentIndex == index ? theme.accentPrimary : .clear, lineWidth: 2)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if let decision = session.decisions[identifier] {
                                        Image(systemName: decision == .delete ? "trash.circle.fill" : "checkmark.circle.fill")
                                            .foregroundStyle(decision == .delete ? theme.negativeRed : theme.positiveGreen)
                                            .background(theme.cardSurface, in: Circle())
                                            .padding(2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(index + 1) / \(session.assetIDs.count)"))
                        .accessibilityIdentifier("media.swipeReview.thumbnail.\(index)")
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.currentIndex) { _, index in
                guard session.assetIDs.indices.contains(index) else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .frame(height: 68)
        .accessibilityIdentifier("media.swipeReview.thumbnails")
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Selection")
                .font(.largeTitle.bold())
            Text(String.localizedStringWithFormat(
                AppL10n.string("%lld kept · %lld marked for deletion"),
                Int64(session.keptCount),
                Int64(session.pendingDeletionIDs.count)
            ))
            .foregroundStyle(theme.textSecondary)
            Text("Nothing has been deleted yet.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)

            if !session.pendingDeletionIDs.isEmpty {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(session.assetIDs.filter { session.pendingDeletionIDs.contains($0) }, id: \.self) { identifier in
                            Button {
                                if let index = session.assetIDs.firstIndex(of: identifier) {
                                    _ = session.selectAsset(at: index)
                                    previewIsReady = false
                                    isShowingSummary = false
                                }
                            } label: {
                                ReviewThumbnail(asset: photoLibrary.asset(withIdentifier: identifier), photoLibrary: photoLibrary, width: 76, height: 84)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "trash.circle.fill")
                                            .foregroundStyle(theme.negativeRed)
                                            .background(theme.cardSurface, in: Circle())
                                            .padding(4)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .accessibilityIdentifier("media.swipeReview.markedGrid")
            } else {
                Spacer()
            }
            if let deletionError {
                Text(deletionError)
                    .font(.subheadline)
                    .foregroundStyle(theme.negativeRed)
                    .multilineTextAlignment(.center)
            }
            if !session.pendingDeletionIDs.isEmpty {
                Button("Delete Marked Media", systemImage: "trash") {
                    confirmation = .delete
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.negativeRed)
                .frame(maxWidth: .infinity)
                .disabled(photoLibrary.deletionState.isDeleting)
                .accessibilityIdentifier("media.swipeReview.confirmDelete")
            }
            HStack {
                Button("Continue Reviewing") {
                    if session.currentAssetID == nil { _ = session.selectAsset(at: 0) }
                    previewIsReady = false
                    isShowingSummary = false
                }
                Spacer()
                Button("Done") { close() }
            }
        }
        .padding(24)
    }

    private func completionView(deletedCount: Int) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(theme.positiveGreen)
            Text("Moved to Recently Deleted")
                .font(.title2.bold())
            Text(String.localizedStringWithFormat(AppL10n.string("%lld items"), Int64(deletedCount)))
            Text("Storage may not be freed until these items are permanently deleted in Photos.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func close() {
        if deletedCount == nil && session.hasDecisions {
            confirmation = .discard
        } else {
            onDismiss()
        }
    }

    private func deleteMarkedMedia() {
        let ids = session.pendingDeletionIDs
        guard !ids.isEmpty else { return }
        deletionError = nil
        Task {
            await photoLibrary.deleteAssets(withIDs: ids)
            switch photoLibrary.deletionState {
            case let .success(count, _): deletedCount = count
            case let .failure(error): deletionError = error.localizedDescription
            default: break // Cancellation leaves the review choices available.
            }
        }
    }
}

private struct ReviewThumbnail: View {
    let asset: PHAsset?
    @ObservedObject var photoLibrary: PhotoLibraryViewModel
    @Environment(\.appTheme) private var theme
    var width: CGFloat = 54
    var height: CGFloat = 64
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
        .frame(width: width, height: height)
        .clipped()
        .onAppear {
            guard let asset else { return }
            image = photoLibrary.cachedThumbnail(for: asset.localIdentifier)
            requestID = photoLibrary.requestThumbnail(
                for: asset, targetSize: CGSize(width: width * displayScale, height: height * displayScale)
            ) { loadedImage in
                if let loadedImage { image = loadedImage }
            }
        }
        .onDisappear {
            if let requestID { photoLibrary.cancelThumbnail(requestID) }
            requestID = nil
        }
    }
}

private struct ReviewAssetCard: View {
    let asset: PHAsset
    @ObservedObject var photoLibrary: PhotoLibraryViewModel
    @Environment(\.appTheme) private var theme
    let onLoadState: (String, Bool) -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var requestedAssetID: String?
    @State private var hasFailed = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasFailed {
                    Label("Media Unavailable", systemImage: "icloud.slash")
                } else {
                    ProgressView("Loading…")
                        .tint(theme.accentPrimary)
                }
                if image != nil && asset.mediaType == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 54))
                        .shadow(radius: 8)
                }
            }
            .task(id: asset.localIdentifier) {
                if let requestID { photoLibrary.cancelThumbnail(requestID) }
                requestID = nil
                requestedAssetID = asset.localIdentifier
                hasFailed = false
                image = photoLibrary.cachedThumbnail(for: asset.localIdentifier)
                requestID = photoLibrary.requestPreviewImage(
                    for: asset,
                    targetSize: CGSize(
                        width: max(geometry.size.width, 1) * displayScale,
                        height: max(geometry.size.height, 1) * displayScale
                    )
                ) { loadedImage in
                    guard requestedAssetID == asset.localIdentifier else { return }
                    image = loadedImage
                    hasFailed = loadedImage == nil
                    onLoadState(asset.localIdentifier, loadedImage != nil)
                }
            }
        }
        .onDisappear {
            if let requestID { photoLibrary.cancelThumbnail(requestID) }
            requestID = nil
            requestedAssetID = nil
        }
        .accessibilityLabel(asset.mediaType == .video ? Text("Video preview") : Text("Photo preview"))
    }
}
