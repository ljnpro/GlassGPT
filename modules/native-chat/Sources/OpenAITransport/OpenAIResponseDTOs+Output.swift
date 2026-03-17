import Foundation

public struct ResponsesContentPartDTO: Codable, Equatable, Sendable {
    public let type: String
    public let text: String?
    public let annotations: [ResponsesAnnotationDTO]?

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

public struct ResponsesActionDTO: Codable, Equatable, Sendable {
    public let query: String?
    public let queries: [String]?

    public init(query: String? = nil, queries: [String]? = nil) {
        self.query = query
        self.queries = queries
    }
}

public struct ResponsesCodeInterpreterOutputDTO: Codable, Equatable, Sendable {
    public let output: String?
    public let text: String?
    public let logs: String?

    public init(output: String? = nil, text: String? = nil, logs: String? = nil) {
        self.output = output
        self.text = text
        self.logs = logs
    }
}

public struct ResponsesOutputItemDTO: Codable, Equatable, Sendable {
    public let type: String
    public let id: String?
    public let content: [ResponsesContentPartDTO]?
    public let action: ResponsesActionDTO?
    public let query: String?
    public let queries: [String]?
    public let code: String?
    public let results: [ResponsesCodeInterpreterOutputDTO]?
    public let outputs: [ResponsesCodeInterpreterOutputDTO]?
    public let text: String?
    public let summary: [ResponsesTextFragmentDTO]?

    public init(
        type: String,
        id: String? = nil,
        content: [ResponsesContentPartDTO]? = nil,
        action: ResponsesActionDTO? = nil,
        query: String? = nil,
        queries: [String]? = nil,
        code: String? = nil,
        results: [ResponsesCodeInterpreterOutputDTO]? = nil,
        outputs: [ResponsesCodeInterpreterOutputDTO]? = nil,
        text: String? = nil,
        summary: [ResponsesTextFragmentDTO]? = nil
    ) {
        self.type = type
        self.id = id
        self.content = content
        self.action = action
        self.query = query
        self.queries = queries
        self.code = code
        self.results = results
        self.outputs = outputs
        self.text = text
        self.summary = summary
    }
}

public struct ResponsesResponseDTO: Codable, Equatable, Sendable {
    public let id: String?
    public let status: String?
    public let sequenceNumber: Int?
    public let outputText: String?
    public let output: [ResponsesOutputItemDTO]?
    public let reasoning: ResponsesReasoningDTO?
    public let error: ResponsesErrorDTO?
    public let message: String?

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

    public init(
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
