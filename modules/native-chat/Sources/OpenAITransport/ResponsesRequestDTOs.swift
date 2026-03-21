import Foundation

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
