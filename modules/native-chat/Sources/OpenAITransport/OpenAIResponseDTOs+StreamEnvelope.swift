/// The JSON envelope wrapping each server-sent event in a streaming response.
public struct ResponsesStreamEnvelopeDTO: Codable, Equatable, Sendable {
    /// An incremental text delta.
    public let delta: String?
    /// The identifier of the output item this event relates to.
    public let itemID: String?
    /// Completed code for a code interpreter call.
    public let code: String?
    /// Full text content for a done event.
    public let text: String?
    /// An annotation added during streaming.
    public let annotation: ResponsesAnnotationDTO?
    /// The full response object for terminal events.
    public let response: ResponsesResponseDTO?
    /// The event sequence number for ordering.
    public let sequenceNumber: Int?
    /// Error information for error events.
    public let error: ResponsesErrorDTO?
    /// An error message string.
    public let message: String?

    /// Creates a new stream envelope DTO.
    public init(
        delta: String? = nil,
        itemID: String? = nil,
        code: String? = nil,
        text: String? = nil,
        annotation: ResponsesAnnotationDTO? = nil,
        response: ResponsesResponseDTO? = nil,
        sequenceNumber: Int? = nil,
        error: ResponsesErrorDTO? = nil,
        message: String? = nil
    ) {
        self.delta = delta
        self.itemID = itemID
        self.code = code
        self.text = text
        self.annotation = annotation
        self.response = response
        self.sequenceNumber = sequenceNumber
        self.error = error
        self.message = message
    }

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

    /// Returns the embedded response, or synthesizes one from top-level envelope fields.
    public var resolvedResponse: ResponsesResponseDTO {
        response ?? ResponsesResponseDTO(
            sequenceNumber: sequenceNumber,
            error: error,
            message: message
        )
    }
}
