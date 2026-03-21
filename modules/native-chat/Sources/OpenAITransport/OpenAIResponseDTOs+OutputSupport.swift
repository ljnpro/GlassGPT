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
