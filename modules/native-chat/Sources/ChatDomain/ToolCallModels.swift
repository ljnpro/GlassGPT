import Foundation

/// The kind of tool invoked by the assistant during a response.
public enum ToolCallType: String, Codable, Sendable, Equatable {
    /// A web search tool invocation.
    case webSearch = "web_search"
    /// A code interpreter tool invocation.
    case codeInterpreter = "code_interpreter"
    /// A file search tool invocation.
    case fileSearch = "file_search"
}

/// The execution status of a tool call.
public enum ToolCallStatus: String, Codable, Sendable, Equatable {
    /// The tool call is currently being processed.
    case inProgress = "in_progress"
    /// The web search tool is actively searching.
    case searching
    /// The code interpreter is executing code.
    case interpreting
    /// The file search tool is scanning files.
    case fileSearching = "file_searching"
    /// The tool call has finished executing.
    case completed
}

/// Information about a tool call made by the assistant during a response.
public struct ToolCallInfo: PayloadCodable, Identifiable, Equatable {
    /// The unique identifier for this tool call.
    public var id: String
    /// The type of tool that was invoked.
    public var type: ToolCallType
    /// The current execution status of the tool call.
    public var status: ToolCallStatus
    /// The source code executed by the code interpreter, if applicable.
    public var code: String?
    /// The output results produced by the tool, if any.
    public var results: [String]?
    /// The search queries issued by the tool, if applicable.
    public var queries: [String]?

    /// Creates a new tool call info instance.
    /// - Parameters:
    ///   - id: The unique identifier for this tool call.
    ///   - type: The type of tool invoked.
    ///   - status: The current execution status.
    ///   - code: Source code for code interpreter calls.
    ///   - results: Output results from the tool.
    ///   - queries: Search queries issued by the tool.
    public init(
        id: String,
        type: ToolCallType,
        status: ToolCallStatus,
        code: String? = nil,
        results: [String]? = nil,
        queries: [String]? = nil
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.code = code
        self.results = results
        self.queries = queries
    }
}
