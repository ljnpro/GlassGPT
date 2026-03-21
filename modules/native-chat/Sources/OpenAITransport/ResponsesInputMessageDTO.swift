import Foundation

/// A message in the Responses API input format.
public struct ResponsesInputMessageDTO: Codable, Equatable, Sendable {
    /// The role of the message sender (e.g. "user", "assistant").
    public let role: String
    /// The message content, either plain text or a list of multi-modal items.
    public let content: Content

    /// Creates a new input message DTO.
    /// - Parameters:
    ///   - role: The message sender role.
    ///   - content: The message content.
    public init(role: String, content: Content) {
        self.role = role
        self.content = content
    }

    /// The content of an input message, which can be plain text or multi-modal items.
    public enum Content: Codable, Equatable, Sendable {
        /// Plain text content.
        case text(String)
        /// A list of multi-modal content items (text, images, files).
        case items([Item])

        /// Decodes either a plain-text input payload or a multi-item payload.
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            do {
                let value = try container.decode(String.self)
                self = .text(value)
                return
            } catch DecodingError.typeMismatch {
                self = try .items(container.decode([Item].self))
            } catch {
                throw error
            }
        }

        /// Encodes the content using the schema expected by the Responses API.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .text(value):
                try container.encode(value)
            case let .items(items):
                try container.encode(items)
            }
        }
    }

    /// A single content item within a multi-modal message.
    public enum Item: Codable, Equatable, Sendable {
        /// A text input item.
        case inputText(String)
        /// An image input item specified by a data URL or image URL.
        case inputImage(String)
        /// A file input item specified by its uploaded file identifier.
        case inputFile(String)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
            case fileID = "file_id"
        }

        /// Decodes a typed multi-modal input item from the Responses API schema.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "input_text":
                self = try .inputText(container.decode(String.self, forKey: .text))
            case "input_image":
                self = try .inputImage(container.decode(String.self, forKey: .imageURL))
            case "input_file":
                self = try .inputFile(container.decode(String.self, forKey: .fileID))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unsupported input item type"
                )
            }
        }

        /// Encodes the item using the Responses API multi-modal input schema.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .inputText(text):
                try container.encode("input_text", forKey: .type)
                try container.encode(text, forKey: .text)
            case let .inputImage(imageURL):
                try container.encode("input_image", forKey: .type)
                try container.encode(imageURL, forKey: .imageURL)
            case let .inputFile(fileID):
                try container.encode("input_file", forKey: .type)
                try container.encode(fileID, forKey: .fileID)
            }
        }
    }
}
