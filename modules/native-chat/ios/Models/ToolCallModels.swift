import Foundation

enum ToolCallType: String, Codable, Sendable, Equatable {
    case webSearch = "web_search"
    case codeInterpreter = "code_interpreter"
    case fileSearch = "file_search"
}

enum ToolCallStatus: String, Codable, Sendable, Equatable {
    case inProgress = "in_progress"
    case searching
    case interpreting
    case fileSearching = "file_searching"
    case completed
}

struct ToolCallInfo: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var type: ToolCallType
    var status: ToolCallStatus
    var code: String?
    var results: [String]?
    var queries: [String]?

    static func encode(_ items: [ToolCallInfo]?) -> Data? {
        guard let items = items, !items.isEmpty else { return nil }
        do {
            return try JSONCoding.encode(items)
        } catch {
            Loggers.persistence.error("[ToolCallInfo.encode] \(error.localizedDescription)")
            return nil
        }
    }

    static func decode(_ data: Data?) -> [ToolCallInfo]? {
        guard let data else { return nil }
        do {
            return try JSONCoding.decode([ToolCallInfo].self, from: data)
        } catch {
            Loggers.persistence.error("[ToolCallInfo.decode] \(error.localizedDescription)")
            return nil
        }
    }
}
