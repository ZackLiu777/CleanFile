//
//  将选定转换结果保存到照片图库，并在同一 PhotoKit 变更中请求删除对应原件。
//  执行前检查媒体类型、输出文件和原件是否存在；系统负责呈现删除确认。
//  仅调用方主动发起替换时执行，返回成功批次的候选标识。
//  审阅页面先确定待处理候选项，再由调用方调用此服务提交 PhotoKit 变更。
//  工作区副本及输出的后续清理由调用方单独处理，不与照片图库变更混为一谈。
//

import Foundation
import Photos

/// 待替换项关联转换输出、照片资源及转换前后的大小。
struct ConversionReplacementCandidate: Identifiable, Hashable, Sendable {
    let id: UUID
    let outputURL: URL
    let photoAssetIdentifier: String
    let kind: ConversionMediaKind
    let sourceBytes: Int64
    let outputBytes: Int64
}

/// 替换前置条件不满足或无法创建照片资源时返回的错误。
enum ConversionOriginalReplacementError: Error {
    case missingOriginal
    case unsupportedOutput
    case missingOutput
    case creationFailed
}

/// 在同一个 PhotoKit 变更中创建所有副本并请求删除原件。
/// 删除确认由系统处理，调用者须先取得用户主动操作。
enum ConversionOriginalReplacementService {
    static let supportedKinds: Set<ConversionMediaKind> = [.image, .video]

    /// 校验所有候选后提交照片图库变更；任何校验失败都不会进入变更块。
    /// 成功时返回候选 ID 集合，系统变更错误向调用方传播。
    static func replace(_ candidates: [ConversionReplacementCandidate]) async throws -> Set<UUID> {
        guard !candidates.isEmpty else { return [] }
        guard candidates.allSatisfy({ supportedKinds.contains($0.kind) }) else {
            throw ConversionOriginalReplacementError.unsupportedOutput
        }
        guard candidates.allSatisfy({ candidate in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate.outputURL.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }) else {
            throw ConversionOriginalReplacementError.missingOutput
        }
        let identifiers = candidates.map(\.photoAssetIdentifier)
        let originals = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard originals.count == identifiers.count else {
            throw ConversionOriginalReplacementError.missingOriginal
        }

        var createdEveryCopy = true
        try await PHPhotoLibrary.shared().performChanges {
            for candidate in candidates {
                let request: PHAssetChangeRequest?
                switch candidate.kind {
                case .image:
                    request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: candidate.outputURL)
                case .video:
                    request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: candidate.outputURL)
                case .audio:
                    // Rejected by the validation above; retained for exhaustive switching.
                    request = nil
                }
                if request == nil {
                    createdEveryCopy = false
                    return
                }
            }
            PHAssetChangeRequest.deleteAssets(originals)
        }
        guard createdEveryCopy else { throw ConversionOriginalReplacementError.creationFailed }
        return Set(candidates.map(\.id))
    }
}
