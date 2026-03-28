import Foundation

public enum ArtifactKindDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case image
    case document
    case code
    case data
}

public struct ArtifactDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let conversationID: String
    public let runID: String
    public let kind: ArtifactKindDTO
    public let filename: String
    public let contentType: String
    public let byteCount: Int
    public let createdAt: Date
    public let downloadURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversationId"
        case runID = "runId"
        case kind
        case filename
        case contentType
        case byteCount
        case createdAt
        case downloadURL = "downloadUrl"
    }
}

public struct ArtifactDownloadDTO: Codable, Equatable, Sendable {
    public let artifact: ArtifactDTO
    public let url: URL
}
