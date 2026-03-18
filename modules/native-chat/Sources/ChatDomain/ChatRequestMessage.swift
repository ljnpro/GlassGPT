import Foundation

public struct ChatRequestMessage: Sendable, Equatable {
    public let role: MessageRole
    public let content: String
    public let imageData: Data?
    public let fileAttachments: [FileAttachment]

    public init(
        role: MessageRole,
        content: String,
        imageData: Data? = nil,
        fileAttachments: [FileAttachment] = []
    ) {
        self.role = role
        self.content = content
        self.imageData = imageData
        self.fileAttachments = fileAttachments
    }
}
