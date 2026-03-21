import Foundation

/// A tool configuration for a Responses API request.
public struct ResponsesToolDTO: Codable, Equatable, Sendable {
    /// The tool type identifier (e.g. "web_search_preview", "code_interpreter").
    public let type: String
    /// Optional container configuration for code interpreter.
    public let container: Container?
    /// Optional vector store IDs for file search.
    public let vectorStoreIDs: [String]?

    /// Creates a new tool configuration DTO.
    /// - Parameters:
    ///   - type: The tool type identifier.
    ///   - container: Optional container configuration.
    ///   - vectorStoreIDs: Optional vector store IDs.
    public init(
        type: String,
        container: Container? = nil,
        vectorStoreIDs: [String]? = nil
    ) {
        self.type = type
        self.container = container
        self.vectorStoreIDs = vectorStoreIDs
    }

    /// Configuration for the code interpreter container.
    public struct Container: Codable, Equatable, Sendable {
        /// The container type (e.g. "auto").
        public let type: String

        /// Creates a new container configuration.
        /// - Parameter type: The container type.
        public init(type: String) {
            self.type = type
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case container
        case vectorStoreIDs = "vector_store_ids"
    }
}
