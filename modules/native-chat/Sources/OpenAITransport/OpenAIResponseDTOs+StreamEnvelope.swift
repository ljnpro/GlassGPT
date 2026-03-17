public struct ResponsesStreamEnvelopeDTO: Codable, Equatable, Sendable {
    public let delta: String?
    public let itemID: String?
    public let code: String?
    public let text: String?
    public let annotation: ResponsesAnnotationDTO?
    public let response: ResponsesResponseDTO?
    public let sequenceNumber: Int?
    public let error: ResponsesErrorDTO?
    public let message: String?

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

    public var resolvedResponse: ResponsesResponseDTO {
        response ?? ResponsesResponseDTO(
            sequenceNumber: sequenceNumber,
            error: error,
            message: message
        )
    }
}
