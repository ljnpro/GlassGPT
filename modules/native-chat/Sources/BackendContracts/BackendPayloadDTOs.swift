import Foundation

public enum ToolCallTypeDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case webSearch = "web_search"
    case codeInterpreter = "code_interpreter"
    case fileSearch = "file_search"
}

public enum ToolCallStatusDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case inProgress = "in_progress"
    case searching
    case interpreting
    case fileSearching = "file_searching"
    case completed
}

public struct ToolCallInfoDTO: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let type: ToolCallTypeDTO
    public let status: ToolCallStatusDTO
    public let code: String?
    public let results: [String]?
    public let queries: [String]?

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

public struct URLCitationDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        "\(startIndex)-\(endIndex)-\(url)"
    }

    public let url: String
    public let title: String
    public let startIndex: Int
    public let endIndex: Int

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
