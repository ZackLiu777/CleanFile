import Photos

/// Serializes synchronous PhotoKit inventory work away from the UI executor.
/// PHAsset objects are immutable metadata references, not decoded image data.
actor MediaLibraryInventory {
    func fetch() throws -> [PHAsset] {
        try Task.checkCancellation()
        let interval = MediaPerformance.begin("Media Fetch Assets")
        defer { MediaPerformance.end("Media Fetch Assets", id: interval) }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        for index in 0..<result.count {
            try Task.checkCancellation()
            assets.append(result.object(at: index))
        }
        return assets
    }
}
