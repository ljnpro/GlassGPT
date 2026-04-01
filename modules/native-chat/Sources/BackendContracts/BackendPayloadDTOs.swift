import Foundation

/// The type of tool invocation within a message.
public enum ToolCallTypeDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case webSearch = "web_search"
    case codeInterpreter = "code_interpreter"
    case fileSearch = "file_search"
}

/// The execution status of a tool call.
public enum ToolCallStatusDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case inProgress = "in_progress"
    case searching
    case interpreting
    case fileSearching = "file_searching"
    case completed
}

/// Metadata about a tool call embedded in an assistant message.
public struct ToolCallInfoDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let type: ToolCallTypeDTO
    public let status: ToolCallStatusDTO
    public let code: String?
    public let results: [String]?
    public let queries: [String]?

    /// Creates a tool call info DTO with the given fields.
    public init(
        id: String,
        type: ToolCallTypeDTO,
        status: ToolCallStatusDTO,
        code: String?,
        results: [String]?,
        queries: [String]?
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.code = code
        self.results = results
        self.queries = queries
    }
}

/// A URL citation annotation attached to assistant message content.
public struct URLCitationDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        "\(startIndex)-\(endIndex)-\(url)"
    }

    public let url: String
    public let title: String
    public let startIndex: Int
    public let endIndex: Int

    /// Creates a URL citation spanning the given character range.
    public init(
        url: String,
        title: String,
        startIndex: Int,
        endIndex: Int
    ) {
        self.url = url
        self.title = title
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

/// An annotation referencing a generated file within a code interpreter sandbox.
public struct FilePathAnnotationDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        "\(startIndex)-\(endIndex)-\(fileId)"
    }

    public let fileId: String
    public let containerId: String?
    public let sandboxPath: String
    public let filename: String?
    public let startIndex: Int
    public let endIndex: Int

    /// Creates a file path annotation for the given sandbox file.
    public init(
        fileId: String,
        containerId: String?,
        sandboxPath: String,
        filename: String?,
        startIndex: Int,
        endIndex: Int
    ) {
        self.fileId = fileId
        self.containerId = containerId
        self.sandboxPath = sandboxPath
        self.filename = filename
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}
