import Foundation

/// The response body from a file upload request.
public struct UploadedFileResponseDTO: Codable, Equatable, Sendable {
    /// The API-assigned file identifier.
    public let id: String

    /// Creates a new uploaded file response DTO.
    /// - Parameter id: The file identifier.
    public init(id: String) {
        self.id = id
    }
}

/// An error object from the API, which may appear as a string or a keyed object.
public struct ResponsesErrorDTO: Codable, Equatable, Sendable {
    /// The error message, if available.
    public let message: String?

    /// Creates a new error DTO.
    /// - Parameter message: The error message.
    public init(message: String?) {
        self.message = message
    }

    /// Decodes an error payload that may arrive as either a string or an object.
    /// Decodes reasoning text, accepting either fragment arrays or string summaries.
    public init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        do {
            let stringValue = try singleValue.decode(String.self)
            message = stringValue
            return
        } catch DecodingError.typeMismatch {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decodeIfPresent(String.self, forKey: .message)
        } catch {
            throw error
        }
    }

    private enum CodingKeys: String, CodingKey {
        case message
    }
}

/// A fragment of text, used in reasoning summaries.
public struct ResponsesTextFragmentDTO: Codable, Equatable, Sendable {
    /// The text content of this fragment.
    public let text: String?

    /// Creates a new text fragment DTO.
    /// - Parameter text: The text content.
    public init(text: String?) {
        self.text = text
    }
}

/// Reasoning data from a response, including full text and summary fragments.
public struct ResponsesReasoningDTO: Codable, Equatable, Sendable {
    /// The full reasoning text, if available.
    public let text: String?
    /// Summary fragments of the reasoning, if available.
    public let summary: [ResponsesTextFragmentDTO]?

    /// Creates a new reasoning DTO.
    public init(text: String?, summary: [ResponsesTextFragmentDTO]?) {
        self.text = text
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case summary
    }

    /// Decodes reasoning text, accepting either fragment arrays or string summaries.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        do {
            summary = try container.decodeIfPresent([ResponsesTextFragmentDTO].self, forKey: .summary)
        } catch DecodingError.typeMismatch {
            _ = try container.decodeIfPresent(String.self, forKey: .summary)
            summary = nil
        }
    }

    /// Encodes this reasoning payload back into the Responses API wire format.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}

/// An annotation attached to response content (URL citation or file path).
public struct ResponsesAnnotationDTO: Codable, Equatable, Sendable {
    /// The annotation type (e.g. "url_citation", "file_path", "container_file_citation").
    public let type: String
    /// The cited URL, for URL citation annotations.
    public let url: String?
    /// The title of the cited source, for URL citations.
    public let title: String?
    /// The start character offset of the annotated span.
    public let startIndex: Int?
    /// The end character offset of the annotated span.
    public let endIndex: Int?
    /// The API file identifier, for file annotations.
    public let fileID: String?
    /// The container identifier, for file annotations.
    public let containerID: String?
    /// The filename, for file annotations.
    public let filename: String?

    /// Creates a new annotation DTO.
    public init(
        type: String,
        url: String? = nil,
        title: String? = nil,
        startIndex: Int? = nil,
        endIndex: Int? = nil,
        fileID: String? = nil,
        containerID: String? = nil,
        filename: String? = nil
    ) {
        self.type = type
        self.url = url
        self.title = title
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.fileID = fileID
        self.containerID = containerID
        self.filename = filename
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case title
        case startIndex = "start_index"
        case endIndex = "end_index"
        case fileID = "file_id"
        case containerID = "container_id"
        case filename
    }
}
