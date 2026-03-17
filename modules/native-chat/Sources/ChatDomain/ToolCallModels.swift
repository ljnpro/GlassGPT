import Foundation

public enum ToolCallType: String, Codable, Sendable, Equatable {
    case webSearch = "web_search"
    case codeInterpreter = "code_interpreter"
    case fileSearch = "file_search"
}

public enum ToolCallStatus: String, Codable, Sendable, Equatable {
    case inProgress = "in_progress"
    case searching
    case interpreting
    case fileSearching = "file_searching"
    case completed
}

public struct ToolCallInfo: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var type: ToolCallType
    public var status: ToolCallStatus
    public var code: String?
    public var results: [String]?
    public var queries: [String]?

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

    public static func encode(_ items: [ToolCallInfo]?) -> Data? {
        guard let items, !items.isEmpty else { return nil }
        do {
            return try PayloadJSONCoding.encode(items)
        } catch {
            return nil
        }
    }

    public static func decode(_ data: Data?) -> [ToolCallInfo]? {
        guard let data else { return nil }
        do {
            return try PayloadJSONCoding.decode([ToolCallInfo].self, from: data)
        } catch {
            return nil
        }
    }
}
