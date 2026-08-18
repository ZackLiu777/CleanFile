//
//  PhotosView.swift
//  CleanMyIPhone
//

import Photos
import SwiftUI
import UIKit

struct PhotosView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()

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
                        photoContent
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
            .navigationTitle("Photos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        viewModel.refresh()
                    }
                }
            }
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        if viewModel.isLoading {
            ProgressView("Loading photos…")
        } else if viewModel.assets.isEmpty {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle",
                description: Text("No images are available in your Photos library.")
            )
        } else {
            photoGrid
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

            photoContent
        }
        .padding(.horizontal)
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 2)],
                spacing: 2
            ) {
                ForEach(viewModel.assets, id: \.localIdentifier) { asset in
                    PhotoThumbnailView(asset: asset, viewModel: viewModel)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    private func permissionView(
        title: String,
        message: String,
        buttonTitle: String?,
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

private struct PhotoThumbnailView: View {
    let asset: PHAsset
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
            } else {
                Rectangle()
                    .fill(.quaternary)
                ProgressView()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: asset.localIdentifier) {
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

        requestID = viewModel.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 300 * displayScale, height: 300 * displayScale)
        ) { loadedImage in
            image = loadedImage
        }
    }
}
