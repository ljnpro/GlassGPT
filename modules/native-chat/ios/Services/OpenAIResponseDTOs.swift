import Foundation

struct UploadedFileResponseDTO: Codable, Equatable, Sendable {
    let id: String
}

struct ResponsesErrorDTO: Codable, Equatable, Sendable {
    let message: String?

    init(message: String?) {
        self.message = message
    }

    init(from decoder: Decoder) throws {
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

struct ResponsesTextFragmentDTO: Codable, Equatable, Sendable {
    let text: String?
}

struct ResponsesReasoningDTO: Codable, Equatable, Sendable {
    let text: String?
    let summary: [ResponsesTextFragmentDTO]?
}

struct ResponsesAnnotationDTO: Codable, Equatable, Sendable {
    let type: String
    let url: String?
    let title: String?
    let startIndex: Int?
    let endIndex: Int?
    let fileID: String?
    let containerID: String?
    let filename: String?

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

struct ResponsesContentPartDTO: Codable, Equatable, Sendable {
    let type: String
    let text: String?
    let annotations: [ResponsesAnnotationDTO]?
}

struct ResponsesActionDTO: Codable, Equatable, Sendable {
    let query: String?
    let queries: [String]?
}

struct ResponsesCodeInterpreterOutputDTO: Codable, Equatable, Sendable {
    let output: String?
    let text: String?
    let logs: String?
}

struct ResponsesOutputItemDTO: Codable, Equatable, Sendable {
    let type: String
    let id: String?
    let content: [ResponsesContentPartDTO]?
    let action: ResponsesActionDTO?
    let query: String?
    let queries: [String]?
    let code: String?
    let results: [ResponsesCodeInterpreterOutputDTO]?
    let outputs: [ResponsesCodeInterpreterOutputDTO]?
    let text: String?
    let summary: [ResponsesTextFragmentDTO]?
}

struct ResponsesResponseDTO: Codable, Equatable, Sendable {
    let id: String?
    let status: String?
    let sequenceNumber: Int?
    let outputText: String?
    let output: [ResponsesOutputItemDTO]?
    let reasoning: ResponsesReasoningDTO?
    let error: ResponsesErrorDTO?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case sequenceNumber = "sequence_number"
        case outputText = "output_text"
        case output
        case reasoning
        case error
        case message
    }

    init(
        id: String? = nil,
        status: String? = nil,
        sequenceNumber: Int? = nil,
        outputText: String? = nil,
        output: [ResponsesOutputItemDTO]? = nil,
        reasoning: ResponsesReasoningDTO? = nil,
        error: ResponsesErrorDTO? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.status = status
        self.sequenceNumber = sequenceNumber
        self.outputText = outputText
        self.output = output
        self.reasoning = reasoning
        self.error = error
        self.message = message
    }
}

struct ResponsesStreamEnvelopeDTO: Codable, Equatable, Sendable {
    let delta: String?
    let itemID: String?
    let code: String?
    let text: String?
    let annotation: ResponsesAnnotationDTO?
    let response: ResponsesResponseDTO?
    let sequenceNumber: Int?
    let error: ResponsesErrorDTO?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case delta
        case itemID = "item_id"
        case code
        case text
        case annotation
        case response
        case sequenceNumber = "sequence_number"
        case error
        case message
    }

    var resolvedResponse: ResponsesResponseDTO {
        response ?? ResponsesResponseDTO(
            sequenceNumber: sequenceNumber,
            error: error,
            message: message
        )
    }
}
