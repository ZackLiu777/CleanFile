//
//  相册资源清单
//
//  在独立 actor 中枚举 PhotoKit 的资源元数据并按创建时间排序。
//  返回的是资源引用而非解码后的图片；枚举期间支持任务取消。
//

import Photos

/// Serializes synchronous PhotoKit inventory work away from the UI executor.
/// PHAsset objects are immutable metadata references, not decoded image data.
actor MediaLibraryInventory {
    /// 按创建时间降序获取资源引用，在逐项枚举时响应取消；不请求图片或视频内容。
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
