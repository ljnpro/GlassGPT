import Foundation

/// A single output item from a response (message, tool call, or reasoning).
public struct ResponsesOutputItemDTO: Codable, Equatable, Sendable {
    /// The output item type (e.g. "message", "web_search_call", "code_interpreter_call").
    public let type: String
    /// The unique identifier of this output item.
    public let id: String?
    /// The output item status, if present.
    public let status: String?
    /// The output item phase, if present.
    public let phase: String?
    /// The output item role, if present.
    public let role: String?
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
        status: String? = nil,
        phase: String? = nil,
        role: String? = nil,
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
        self.status = status
        self.phase = phase
        self.role = role
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

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case status
        case phase
        case role
        case content
        case action
        case query
        case queries
        case code
        case results
        case outputs
        case text
        case summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        content = try container.decodeIfPresent([ResponsesContentPartDTO].self, forKey: .content)
        action = try container.decodeIfPresent(ResponsesActionDTO.self, forKey: .action)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        queries = try container.decodeIfPresent([String].self, forKey: .queries)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        results = try container.decodeIfPresent([ResponsesCodeInterpreterOutputDTO].self, forKey: .results)
        outputs = try container.decodeIfPresent([ResponsesCodeInterpreterOutputDTO].self, forKey: .outputs)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        do {
            summary = try container.decodeIfPresent([ResponsesTextFragmentDTO].self, forKey: .summary)
        } catch DecodingError.typeMismatch {
            _ = try container.decodeIfPresent(String.self, forKey: .summary)
            summary = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(phase, forKey: .phase)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(query, forKey: .query)
        try container.encodeIfPresent(queries, forKey: .queries)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(results, forKey: .results)
        try container.encodeIfPresent(outputs, forKey: .outputs)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}
