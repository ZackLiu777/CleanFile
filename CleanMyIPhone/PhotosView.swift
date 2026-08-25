//
//  PhotosView.swift
//  CleanMyIPhone
//

import Photos
import SwiftUI
import UIKit

struct PhotosView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Group {
                    switch viewModel.authorizationStatus {
                    case .notDetermined:
                        permissionView(
                            title: "Access your photos",
                            message: "Allow access to display the images in your Photos library.",
                            buttonTitle: "Allow Photo Access",
                            action: viewModel.requestAccess
                        )
                    case .authorized:
                        mediaContent
                    case .limited:
                        limitedPhotoContent
                    case .denied:
                        permissionView(
                            title: "Photo access is off",
                            message: "Enable Photos access in Settings to display your images.",
                            buttonTitle: "Open Settings",
                            action: viewModel.openSettings
                        )
                    case .restricted:
                        permissionView(
                            title: "Photo access is restricted",
                            message: "This device currently prevents the app from accessing Photos.",
                            buttonTitle: nil,
                            action: {}
                        )
                    @unknown default:
                        permissionView(
                            title: "Photo access is unavailable",
                            message: "The current Photos authorization state is not supported.",
                            buttonTitle: nil,
                            action: {}
                        )
                    }
                }
            }
            .navigationTitle("Media")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if viewModel.analysisState.isAnalyzing {
                        Button("Cancel Analysis", role: .cancel) {
                            viewModel.cancelAnalysis()
                        }
                    } else {
                        Button("Analyze") {
                            viewModel.startAnalysis()
                        }
                        .disabled(viewModel.assets.isEmpty || viewModel.isLoading)
                    }

                    Button("Refresh") {
                        viewModel.refresh()
                    }
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading media…")
        } else if viewModel.assets.isEmpty {
            ContentUnavailableView(
                "No Media",
                systemImage: "photo.on.rectangle",
                description: Text("No photos or videos are available in your library.")
            )
        } else {
            mediaDashboard
        }
    }

    @ViewBuilder
    private var limitedPhotoContent: some View {
        VStack(spacing: 12) {
            Label("Limited Photo Access", systemImage: "photo.badge.checkmark")
                .font(.headline)

            Text("Only the photos you selected are available to CleanMyIPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Manage Selected Photos") {
                viewModel.presentLimitedLibraryPicker()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accentPrimary)

            mediaContent
        }
        .padding(.horizontal)
    }

    private var mediaDashboard: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                storageOverview
                analysisContent
            }
            .padding()
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    @ViewBuilder
    private var analysisContent: some View {
        switch viewModel.analysisState {
        case .idle:
            VStack(alignment: .leading, spacing: 14) {
                Label("Smart Media Analysis", systemImage: "sparkles")
                    .font(.title2.bold())
                Text("Find visually similar photos and organize videos, screenshots, and Live Photos.")
                    .foregroundStyle(.secondary)
                Button {
                    viewModel.startAnalysis()
                } label: {
                    Label("Find Similar Photos and Videos", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentPrimary)
            }
            .mediaAnalysisCard()

        case .analyzing(let progress):
            VStack(alignment: .leading, spacing: 10) {
                Text(analysisTitle(for: progress.phase))
                    .font(.headline)
                ProgressView(value: progress.fractionCompleted)
                    .tint(AppTheme.accentPrimary)
                Text("Analyzed \(progress.completed) of \(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .mediaAnalysisCard()

        case .success(let result):
            MediaDashboardResultsView(
                result: result,
                isPartial: false,
                viewModel: viewModel
            )

        case .partialFailure(let result):
            MediaDashboardResultsView(
                result: result,
                isPartial: true,
                viewModel: viewModel
            )

        case .empty:
            Label("No media is available to analyze.", systemImage: "photo.on.rectangle")
                .mediaAnalysisCard()

        case .cancelled:
            VStack(alignment: .leading, spacing: 12) {
                Label("Analysis cancelled. No files were changed.", systemImage: "pause.circle")
                Button("Analyze Again") {
                    viewModel.startAnalysis()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentPrimary)
            }
            .mediaAnalysisCard()

        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .mediaAnalysisCard()
        }
    }

    @ViewBuilder
    private var storageOverview: some View {
        if let storage = viewModel.storageSnapshot {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Device Storage")
                        .font(.title2.bold())
                    Spacer()
                    Text(
                        "\(byteCountText(storage.usedBytes)) of \(byteCountText(storage.totalBytes)) used"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                ProgressView(value: storage.usedFraction)
                    .tint(AppTheme.accentPrimary)

                HStack {
                    Label("Used", systemImage: "internaldrive.fill")
                    Spacer()
                    Text("\(byteCountText(storage.availableBytes)) available")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .mediaAnalysisCard()
        }
    }

    private func byteCountText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func analysisTitle(for phase: MediaAnalysisPhase) -> LocalizedStringKey {
        switch phase {
        case .discovering: "Classifying videos…"
        case .generatingFeatures: "Analyzing image features…"
        case .comparingImages: "Grouping similar photos…"
        }
    }

    private func permissionView(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        buttonTitle: LocalizedStringKey?,
        action: @escaping () -> Void
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "photo.on.rectangle")
        } description: {
            Text(message)
        } actions: {
            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentPrimary)
            }
        }
    }
}

private struct MediaDashboardResultsView: View {
    let result: MediaClassificationResult
    let isPartial: Bool
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Analysis Complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accentPrimary)
                Spacer()
                Text("Select items to delete")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                categoryLink(
                    title: String(localized: "Similar Photos"),
                    detail: itemCount(result.similarImageCount),
                    assetIDs: result.similarImageIDs,
                    systemImage: "photo.stack"
                )
                categoryLink(
                    title: String(localized: "Videos"),
                    detail: itemCount(result.videoIDs.count),
                    assetIDs: result.videoIDs,
                    systemImage: "video.fill"
                )
                categoryLink(
                    title: String(localized: "Screenshots"),
                    detail: itemCount(result.screenshotIDs.count),
                    assetIDs: result.screenshotIDs,
                    systemImage: "iphone"
                )
                categoryLink(
                    title: String(localized: "Live Photos"),
                    detail: itemCount(result.livePhotoIDs.count),
                    assetIDs: result.livePhotoIDs,
                    systemImage: "livephoto"
                )
            }

            videoBreakdown

            if isPartial {
                Label(
                    "\(result.skippedImageCount) iCloud or unavailable image(s) were skipped.",
                    systemImage: "icloud.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("Analysis never deletes media automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            viewModel.startCachingThumbnails(
                for: Array(previewCacheIDs).prefix(80),
                targetSize: thumbnailTargetSize
            )
        }
        .onDisappear {
            viewModel.stopCachingThumbnails(
                for: Array(previewCacheIDs).prefix(80),
                targetSize: thumbnailTargetSize
            )
        }
    }

    private var previewCacheIDs: [String] {
        var seen = Set<String>()
        return (
            result.similarImageIDs.prefix(24)
            + result.videoIDs.prefix(24)
            + result.screenshotIDs.prefix(24)
            + result.livePhotoIDs.prefix(24)
        ).filter { seen.insert($0).inserted }
    }

    private var thumbnailTargetSize: CGSize {
        let pixelWidth = 140 * displayScale
        return CGSize(width: pixelWidth, height: pixelWidth)
    }

    private var videoBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Video Categories")
                .font(.headline)

            ForEach(VideoCategory.allCases, id: \.self) { category in
                let ids = result.classifiedVideos
                    .filter { $0.categories.contains(category) }
                    .map(\.id)
                NavigationLink {
                    MediaCategoryDetailView(
                        title: category.displayName,
                        assetIDs: ids,
                        viewModel: viewModel
                    )
                } label: {
                    HStack {
                        Text(category.displayName)
                        Spacer()
                        Text(String(ids.count))
                            .foregroundStyle(AppTheme.accentPrimary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .mediaAnalysisCard()
    }

    private func categoryLink(
        title: String,
        detail: String,
        assetIDs: [String],
        systemImage: String
    ) -> some View {
        NavigationLink {
            MediaCategoryDetailView(
                title: title,
                assetIDs: assetIDs,
                viewModel: viewModel
            )
        } label: {
            MediaCategoryCard(
                title: title,
                detail: detail,
                representativeAssetID: assetIDs.first,
                systemImage: systemImage,
                viewModel: viewModel
            )
        }
        .buttonStyle(.plain)
        .disabled(assetIDs.isEmpty)
    }

    private func itemCount(_ count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "%lld items"), Int64(count))
    }
}

private struct MediaCategoryCard: View {
    let title: String
    let detail: String
    let representativeAssetID: String?
    let systemImage: String
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let representativeAssetID {
                    GeometryReader { proxy in
                        MediaAssetThumbnailView(
                            assetID: representativeAssetID,
                            viewModel: viewModel
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    Image(systemName: systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(representativeAssetID == nil ? 0.62 : 1)
    }
}

private struct MediaCategoryDetailView: View {
    let title: String
    let assetIDs: [String]
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var isSelecting = false
    @State private var selectedIDs = Set<String>()
    @State private var isDeleteConfirmationPresented = false
    @State private var previewAssetID: String?
    @State private var suppressedTapAssetID: String?

    private let albumColumns = [
        GridItem(.flexible(minimum: 0), spacing: 3),
        GridItem(.flexible(minimum: 0), spacing: 3),
        GridItem(.flexible(minimum: 0), spacing: 3)
    ]

    private var visibleAssetIDs: [String] {
        assetIDs.filter { viewModel.asset(withIdentifier: $0) != nil }
    }

    private var preheatedAssetIDs: ArraySlice<String> {
        visibleAssetIDs.prefix(60)
    }

    private var thumbnailTargetSize: CGSize {
        let pixelWidth = 140 * displayScale
        return CGSize(width: pixelWidth, height: pixelWidth)
    }

    var body: some View {
        Group {
            if visibleAssetIDs.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "photo.on.rectangle",
                    description: Text("No media matched this category.")
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: albumColumns,
                        spacing: 3
                    ) {
                        ForEach(visibleAssetIDs, id: \.self) { assetID in
                            Button {
                                if suppressedTapAssetID == assetID {
                                    suppressedTapAssetID = nil
                                    return
                                }
                                if isSelecting {
                                    toggleSelection(assetID)
                                } else {
                                    previewAssetID = assetID
                                }
                            } label: {
                                Rectangle()
                                    .fill(.clear)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        MediaAssetThumbnailView(
                                            assetID: assetID,
                                            viewModel: viewModel
                                        )
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        selectionIndicator(for: assetID)
                                    }
                                    .contentShape(Rectangle())
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.45)
                                    .onEnded { _ in
                                        suppressedTapAssetID = assetID
                                        isSelecting = true
                                        selectedIDs.insert(assetID)
                                    }
                            )
                        }
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button(selectedIDs.count == visibleAssetIDs.count ? "Deselect All" : "Select All") {
                        if selectedIDs.count == visibleAssetIDs.count {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = Set(visibleAssetIDs)
                        }
                    }
                    Button("Done") {
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                } else {
                    Button("Select") {
                        isSelecting = true
                    }
                    .disabled(visibleAssetIDs.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedIDs.count) selected")
                            .font(.subheadline.weight(.semibold))
                        Text("Estimated \(selectedMediaSizeText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        if viewModel.deletionState.isDeleting {
                            ProgressView()
                        } else {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.red)
                    .disabled(selectedIDs.isEmpty || viewModel.deletionState.isDeleting)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .alert("Delete selected media?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let ids = selectedIDs
                Task {
                    await viewModel.deleteAssets(withIDs: ids)
                    if case .success = viewModel.deletionState {
                        selectedIDs.removeAll()
                        isSelecting = false
                    }
                }
            }
        } message: {
            Text("The system will ask you to confirm deletion of \(selectedIDs.count) photo or video item(s).")
        }
        .alert(
            deletionResultTitle ?? "",
            isPresented: Binding(
                get: { deletionResultTitle != nil },
                set: { if !$0 { viewModel.clearDeletionResult() } }
            )
        ) {
            Button("OK") { viewModel.clearDeletionResult() }
        } message: {
            Text(deletionResultMessage)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { previewAssetID != nil },
                set: { if !$0 { previewAssetID = nil } }
            )
        ) {
            if let previewAssetID {
                MediaPreviewGallery(
                    assetIDs: visibleAssetIDs,
                    initialAssetID: previewAssetID,
                    viewModel: viewModel,
                    onDismiss: { self.previewAssetID = nil }
                )
            }
        }
        .onAppear {
            viewModel.startCachingThumbnails(
                for: preheatedAssetIDs,
                targetSize: thumbnailTargetSize
            )
        }
        .onDisappear {
            viewModel.stopCachingThumbnails(
                for: preheatedAssetIDs,
                targetSize: thumbnailTargetSize
            )
        }
    }

    private func toggleSelection(_ assetID: String) {
        if selectedIDs.contains(assetID) {
            selectedIDs.remove(assetID)
        } else {
            selectedIDs.insert(assetID)
        }
    }

    private var selectedMediaSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: viewModel.estimatedByteCount(for: selectedIDs),
            countStyle: .file
        )
    }

    @ViewBuilder
    private func selectionIndicator(for assetID: String) -> some View {
        if isSelecting {
            Image(systemName: selectedIDs.contains(assetID)
                ? "checkmark.circle.fill"
                : "circle")
                .font(.title2)
                .foregroundStyle(
                    selectedIDs.contains(assetID)
                        ? AppTheme.accentPrimary
                        : .white
                )
                .shadow(radius: 2)
                .padding(6)
        }
    }

    private var deletionResultTitle: String? {
        switch viewModel.deletionState {
        case .success: String(localized: "Deletion Complete")
        case .failure: String(localized: "Deletion Failed")
        default: nil
        }
    }

    private var deletionResultMessage: String {
        switch viewModel.deletionState {
        case .success(let count):
            String.localizedStringWithFormat(String(localized: "%lld media item(s) deleted."), Int64(count))
        case .failure(let error):
            error.localizedDescription
        default:
            ""
        }
    }
}

private struct MediaAssetThumbnailView: View {
    let assetID: String
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(.quaternary)
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: assetID) {
            loadImage()
        }
        .onDisappear {
            if let requestID {
                viewModel.cancelThumbnail(requestID)
            }
        }
    }

    private func loadImage() {
        guard image == nil else { return }
        if let cachedImage = viewModel.cachedThumbnail(for: assetID) {
            image = cachedImage
            return
        }
        guard let asset = viewModel.asset(withIdentifier: assetID) else { return }

        requestID = viewModel.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 140 * displayScale, height: 140 * displayScale)
        ) { loadedImage in
            image = loadedImage
        }
    }
}

private extension View {
    func mediaAnalysisCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground).opacity(0.92),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
    }
}
