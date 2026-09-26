import Foundation

public struct ShareImportRequest: Identifiable, Sendable {
    public enum Kind: Sendable { case image, video }

    public struct File: Identifiable, Sendable {
        public let id: UUID
        public let url: URL

        public init(id: UUID, url: URL) {
            self.id = id
            self.url = url
        }
    }

    public let id: UUID
    public let batchID: UUID
    public let kind: Kind
    public let files: [File]

    public init(id: UUID = UUID(), batchID: UUID, kind: Kind, files: [File]) {
        self.id = id
        self.batchID = batchID
        self.kind = kind
        self.files = files
    }
}
