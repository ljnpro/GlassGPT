import Foundation

/// A content part within a response output item (e.g. text with annotations).
public struct ResponsesContentPartDTO: Codable, Equatable, Sendable {
    /// The content part type (e.g. "output_text").
    public let type: String
    /// The text content, if this is a text part.
    public let text: String?
    /// Annotations attached to this content part, if any.
    public let annotations: [ResponsesAnnotationDTO]?

    /// Creates a new content part DTO.
    public init(
        type: String,
        text: String? = nil,
        annotations: [ResponsesAnnotationDTO]? = nil
    ) {
        self.type = type
        self.text = text
        self.annotations = annotations
    }
}

/// The action data from a tool call (e.g. web search queries).
public struct ResponsesActionDTO: Codable, Equatable, Sendable {
    /// A single search query, if applicable.
    public let query: String?
    /// Multiple search queries, if applicable.
    public let queries: [String]?

    /// Creates a new action DTO.
    public init(query: String? = nil, queries: [String]? = nil) {
        self.query = query
        self.queries = queries
    }
}

/// Output from a code interpreter execution.
public struct ResponsesCodeInterpreterOutputDTO: Codable, Equatable, Sendable {
    /// The execution output string.
    public let output: String?
    /// The text result from execution.
    public let text: String?
    /// The execution logs.
    public let logs: String?

    /// Creates a new code interpreter output DTO.
    public init(output: String? = nil, text: String? = nil, logs: String? = nil) {
        self.output = output
        self.text = text
        self.logs = logs
    }
}

/// A single output item from a response (message, tool call, or reasoning).
public struct ResponsesOutputItemDTO: Codable, Equatable, Sendable {
    /// The output item type (e.g. "message", "web_search_call", "code_interpreter_call").
    public let type: String
    /// The unique identifier of this output item.
    public let id: String?
    /// The content parts for message-type items.
    public let content: [ResponsesContentPartDTO]?
    /// The action data for tool call items.
    public let action: ResponsesActionDTO?
    /// A single query string for search tools.
    public let query: String?
    /// Multiple query strings for search tools.
    public let queries: [String]?
    /// The source code for code interpreter calls.
    public let code: String?
    /// The results from code interpreter execution.
    public let results: [ResponsesCodeInterpreterOutputDTO]?
    /// Alternative output array from code interpreter execution.
    public let outputs: [ResponsesCodeInterpreterOutputDTO]?
    /// Direct text content for reasoning items.
    public let text: String?
    /// Summary fragments for reasoning items.
    public let summary: [ResponsesTextFragmentDTO]?

    /// Creates a new output item DTO.
    public init(
        type: String,
        id: String? = nil,
        content: [ResponsesContentPartDTO]? = nil,
        action: ResponsesActionDTO? = nil,
        query: String? = nil,
        queries: [String]? = nil,
        code: String? = nil,
        results: [ResponsesCodeInterpreterOutputDTO]? = nil,
        outputs: [ResponsesCodeInterpreterOutputDTO]? = nil,
        text: String? = nil,
        summary: [ResponsesTextFragmentDTO]? = nil
    ) {
        self.type = type
        self.id = id
        self.content = content
        self.action = action
        self.query = query
        self.queries = queries
        self.code = code
        self.results = results
        self.outputs = outputs
        self.text = text
        self.summary = summary
    }
}

/// The top-level response object from the Responses API.
public struct ResponsesResponseDTO: Codable, Equatable, Sendable {
    /// The response identifier.
    public let id: String?
    /// The response status (e.g. "completed", "in_progress", "failed").
    public let status: String?
    /// The event sequence number for this response.
    public let sequenceNumber: Int?
    /// Convenience accessor for the full output text, if available.
    public let outputText: String?
    /// The output items produced by the response.
    public let output: [ResponsesOutputItemDTO]?
    /// Reasoning data, if reasoning was enabled.
    public let reasoning: ResponsesReasoningDTO?
    /// Error information, if the response failed.
    public let error: ResponsesErrorDTO?
    /// An error message string, if present.
    public let message: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case sequenceNumber = "sequence_number"
        case outputText = "output_text"
        case output
        case reasoning
        case error
        case message
    }

    /// Creates a new response DTO.
    public init(
        id: String? = nil,
        status: String? = nil,
        sequenceNumber: Int? = nil,
        outputText: String? = nil,
        output: [ResponsesOutputItemDTO]? = nil,
        reasoning: ResponsesReasoningDTO? = nil,
        error: ResponsesErrorDTO? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.status = status
        self.sequenceNumber = sequenceNumber
        self.outputText = outputText
        self.output = output
        self.reasoning = reasoning
        self.error = error
        self.message = message
    }
}
