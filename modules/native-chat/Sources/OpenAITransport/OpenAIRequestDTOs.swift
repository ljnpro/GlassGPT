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

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            do {
                let value = try container.decode(String.self)
                self = .text(value)
                return
            } catch DecodingError.typeMismatch {
                self = .items(try container.decode([Item].self))
            } catch {
                throw error
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(value)
            case .items(let items):
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

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "input_text":
                self = .inputText(try container.decode(String.self, forKey: .text))
            case "input_image":
                self = .inputImage(try container.decode(String.self, forKey: .imageURL))
            case "input_file":
                self = .inputFile(try container.decode(String.self, forKey: .fileID))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unsupported input item type"
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .inputText(let text):
                try container.encode("input_text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .inputImage(let imageURL):
                try container.encode("input_image", forKey: .type)
                try container.encode(imageURL, forKey: .imageURL)
            case .inputFile(let fileID):
                try container.encode("input_file", forKey: .type)
                try container.encode(fileID, forKey: .fileID)
            }
        }
    }
}

/// A tool configuration for a Responses API request.
public struct ResponsesToolDTO: Codable, Equatable, Sendable {
    /// The tool type identifier (e.g. "web_search_preview", "code_interpreter").
    public let type: String
    /// Optional container configuration for code interpreter.
    public let container: Container?
    /// Optional vector store IDs for file search.
    public let vectorStoreIDs: [String]?

    /// Creates a new tool configuration DTO.
    /// - Parameters:
    ///   - type: The tool type identifier.
    ///   - container: Optional container configuration.
    ///   - vectorStoreIDs: Optional vector store IDs.
    public init(
        type: String,
        container: Container? = nil,
        vectorStoreIDs: [String]? = nil
    ) {
        self.type = type
        self.container = container
        self.vectorStoreIDs = vectorStoreIDs
    }

    /// Configuration for the code interpreter container.
    public struct Container: Codable, Equatable, Sendable {
        /// The container type (e.g. "auto").
        public let type: String

        /// Creates a new container configuration.
        /// - Parameter type: The container type.
        public init(type: String) {
            self.type = type
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case container
        case vectorStoreIDs = "vector_store_ids"
    }
}

/// Reasoning configuration for a Responses API request.
public struct ResponsesReasoningRequestDTO: Codable, Equatable, Sendable {
    /// The reasoning effort level (e.g. "low", "medium", "high").
    public let effort: String
    /// The summary mode for reasoning output (e.g. "auto").
    public let summary: String

    /// Creates a new reasoning request DTO.
    /// - Parameters:
    ///   - effort: The reasoning effort level.
    ///   - summary: The summary mode.
    public init(effort: String, summary: String) {
        self.effort = effort
        self.summary = summary
    }
}

/// The request body for a streaming Responses API call.
public struct ResponsesStreamRequestDTO: Codable, Equatable, Sendable {
    /// The model identifier to use.
    public let model: String
    /// The input messages for the conversation.
    public let input: [ResponsesInputMessageDTO]
    /// Whether to stream the response.
    public let stream: Bool
    /// Whether to persist the response on the server.
    public let store: Bool
    /// The service tier for this request.
    public let serviceTier: String
    /// The tools enabled for this request.
    public let tools: [ResponsesToolDTO]
    /// Whether background mode is enabled, or `nil` to omit.
    public let background: Bool?
    /// Optional reasoning configuration, or `nil` to disable reasoning.
    public let reasoning: ResponsesReasoningRequestDTO?

    /// Creates a new stream request DTO.
    public init(
        model: String,
        input: [ResponsesInputMessageDTO],
        stream: Bool,
        store: Bool,
        serviceTier: String,
        tools: [ResponsesToolDTO],
        background: Bool?,
        reasoning: ResponsesReasoningRequestDTO?
    ) {
        self.model = model
        self.input = input
        self.stream = stream
        self.store = store
        self.serviceTier = serviceTier
        self.tools = tools
        self.background = background
        self.reasoning = reasoning
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case stream
        case store
        case serviceTier = "service_tier"
        case tools
        case background
        case reasoning
    }
}

/// The request body for a title generation API call.
public struct ResponsesTitleRequestDTO: Codable, Equatable, Sendable {
    /// The model identifier to use for title generation.
    public let model: String
    /// System instructions for the title generation task.
    public let instructions: String
    /// The input messages to summarize.
    public let input: [ResponsesInputMessageDTO]
    /// Whether to stream the response.
    public let stream: Bool
    /// The maximum number of tokens in the generated title.
    public let maxOutputTokens: Int

    /// Creates a new title request DTO.
    public init(
        model: String,
        instructions: String,
        input: [ResponsesInputMessageDTO],
        stream: Bool,
        maxOutputTokens: Int
    ) {
        self.model = model
        self.instructions = instructions
        self.input = input
        self.stream = stream
        self.maxOutputTokens = maxOutputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case stream
        case maxOutputTokens = "max_output_tokens"
    }
}
