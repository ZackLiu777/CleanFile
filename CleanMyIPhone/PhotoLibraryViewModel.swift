//
//  PhotoLibraryViewModel.swift
//  CleanMyIPhone
//

import Combine
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var isLoading = false

    private let imageManager = PHCachingImageManager()
    private let isRunningInPreviews: Bool

    init() {
        let environment = ProcessInfo.processInfo.environment
        isRunningInPreviews = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        authorizationStatus = isRunningInPreviews
            ? .notDetermined
            : PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func refresh() {
        guard !isRunningInPreviews else { return }

        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            assets = []
            return
        }

        fetchAssets()
    }

    func requestAccess() {
        guard !isRunningInPreviews else { return }

        isLoading = true

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.authorizationStatus = status
                self?.isLoading = false
                self?.fetchAssetsIfAllowed()
            }
        }
    }

    func presentLimitedLibraryPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootViewController = windowScene.windows
                .first(where: \.isKeyWindow)?.rootViewController else {
            return
        }

        var presenter = rootViewController
        while let presentedViewController = presenter.presentedViewController {
            presenter = presentedViewController
        }

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            Task { @MainActor in
                completion(image)
            }
        }
    }

    func cancelThumbnail(_ requestID: PHImageRequestID) {
        imageManager.cancelImageRequest(requestID)
    }

    private func fetchAssetsIfAllowed() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            assets = []
            return
        }

        fetchAssets()
    }

    private func fetchAssets() {
        isLoading = true

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)

        var fetchedAssets: [PHAsset] = []
        fetchedAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }

        assets = fetchedAssets
        isLoading = false
    }
}
