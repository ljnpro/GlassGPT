import Foundation

/// Generic request body for Responses API create calls.
public struct ResponsesCreateRequestDTO: Codable, Equatable, Sendable {
    /// The model identifier to use.
    public let model: String
    /// Optional system or developer instructions.
    public let instructions: String?
    /// Optional previous response identifier used for server-side conversation state.
    public let previousResponseID: String?
    /// The input messages for the request.
    public let input: [ResponsesInputMessageDTO]
    /// Whether to stream the response.
    public let stream: Bool
    /// Whether to persist the response server-side.
    public let store: Bool?
    /// Optional service tier string.
    public let serviceTier: String?
    /// Optional enabled tools.
    public let tools: [ResponsesToolDTO]?
    /// Optional background mode flag.
    public let background: Bool?
    /// Optional reasoning configuration.
    public let reasoning: ResponsesReasoningRequestDTO?
    /// Optional max output token limit.
    public let maxOutputTokens: Int?

    /// Creates a generic Responses API create payload with optional state, tools, and reasoning settings.
    public init(
        model: String,
        instructions: String? = nil,
        previousResponseID: String? = nil,
        input: [ResponsesInputMessageDTO],
        stream: Bool,
        store: Bool? = nil,
        serviceTier: String? = nil,
        tools: [ResponsesToolDTO]? = nil,
        background: Bool? = nil,
        reasoning: ResponsesReasoningRequestDTO? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.previousResponseID = previousResponseID
        self.input = input
        self.stream = stream
        self.store = store
        self.serviceTier = serviceTier
        self.tools = tools
        self.background = background
        self.reasoning = reasoning
        self.maxOutputTokens = maxOutputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case previousResponseID = "previous_response_id"
        case input
        case stream
        case store
        case serviceTier = "service_tier"
        case tools
        case background
        case reasoning
        case maxOutputTokens = "max_output_tokens"
    }
}
