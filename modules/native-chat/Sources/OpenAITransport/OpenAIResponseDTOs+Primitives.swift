import Foundation

public struct UploadedFileResponseDTO: Codable, Equatable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct ResponsesErrorDTO: Codable, Equatable, Sendable {
    public let message: String?

    public init(message: String?) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        do {
            let stringValue = try singleValue.decode(String.self)
            self.message = stringValue
            return
        } catch DecodingError.typeMismatch {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.message = try container.decodeIfPresent(String.self, forKey: .message)
        } catch {
            throw error
        }
    }

    private enum CodingKeys: String, CodingKey {
        case message
    }
}

public struct ResponsesTextFragmentDTO: Codable, Equatable, Sendable {
    public let text: String?

    public init(text: String?) {
        self.text = text
    }
}

public struct ResponsesReasoningDTO: Codable, Equatable, Sendable {
    public let text: String?
    public let summary: [ResponsesTextFragmentDTO]?

    public init(text: String?, summary: [ResponsesTextFragmentDTO]?) {
        self.text = text
        self.summary = summary
    }
}

public struct ResponsesAnnotationDTO: Codable, Equatable, Sendable {
    public let type: String
    public let url: String?
    public let title: String?
    public let startIndex: Int?
    public let endIndex: Int?
    public let fileID: String?
    public let containerID: String?
    public let filename: String?

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
