//
//  定义分享扩展交给转换流程的导入批次、媒体类型和文件标识。
//  每个文件携带独立标识和 URL，批次关联上游分享请求。
//  此模型只传递信息，文件访问和持久化由接收方处理。
//  宿主可将同一分享批次传给转换首页，由首页再交给相应媒体转换页面。
//  标识用于关联接收结果；持有 URL 本身不保证文件始终可访问。
//

import Foundation

/// 从分享入口提交给转换流程的一批同类文件。
public struct ShareImportRequest: Identifiable, Sendable {
    /// 分享批次支持的图片或视频类别。
    public enum Kind: Sendable { case image, video }

    /// 分享批次中的文件标识及其 URL。
    public struct File: Identifiable, Sendable {
        public let id: UUID
        public let url: URL

        /// 保留接收方用于关联导入文件的标识和路径。
        public init(id: UUID, url: URL) {
            self.id = id
            self.url = url
        }
    }

    public let id: UUID
    public let batchID: UUID
    public let kind: Kind
    public let files: [File]

    /// 关联批次标识、媒体类型和文件列表。
    public init(id: UUID = UUID(), batchID: UUID, kind: Kind, files: [File]) {
        self.id = id
        self.batchID = batchID
        self.kind = kind
        self.files = files
    }
}
