import Foundation

/// The top-level response object from the Responses API.
public struct ResponsesResponseDTO: Codable, Equatable, Sendable {
    /// The response identifier.
    public let id: String?
    /// The response status (e.g. "completed", "in_progress", "failed").
    public let status: String?
    /// The event sequence number for this response.
    public let sequenceNumber: Int?
    /// Convenience accessor for the full output text, if available.
    public let outputText: String?
    /// The output items produced by the response.
    public let output: [ResponsesOutputItemDTO]?
    /// Reasoning data, if reasoning was enabled.
    public let reasoning: ResponsesReasoningDTO?
    /// Error information, if the response failed.
    public let error: ResponsesErrorDTO?
    /// An error message string, if present.
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

    /// Creates a new response DTO.
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
