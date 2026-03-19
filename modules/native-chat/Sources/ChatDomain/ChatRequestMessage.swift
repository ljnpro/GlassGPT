import Foundation

/// A single message to be sent as part of a chat completion request.
public struct ChatRequestMessage: Sendable, Equatable {
    /// The role of the message author (user, assistant, or system).
    public let role: MessageRole
    /// The text content of the message.
    public let content: String
    /// Optional image data to include as a vision input.
    public let imageData: Data?
    /// Files attached to this message for upload to the API.
    public let fileAttachments: [FileAttachment]

    /// Creates a new chat request message.
    /// - Parameters:
    ///   - role: The role of the message author.
    ///   - content: The text content of the message.
    ///   - imageData: Optional image data for vision input.
    ///   - fileAttachments: Files to attach to the message.
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
