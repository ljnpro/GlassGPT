import Foundation

public enum HealthCheckStateDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case healthy
    case degraded
    case unavailable
    case missing
    case invalid
    case unauthorized
}

public struct ConnectionCheckDTO: Codable, Equatable, Sendable {
    public let backend: HealthCheckStateDTO
    public let auth: HealthCheckStateDTO
    public let openaiCredential: HealthCheckStateDTO
    public let sse: HealthCheckStateDTO
    public let checkedAt: Date
    public let latencyMilliseconds: Int?
    public let errorSummary: String?

    public init(
        backend: HealthCheckStateDTO,
        auth: HealthCheckStateDTO,
        openaiCredential: HealthCheckStateDTO,
        sse: HealthCheckStateDTO,
        checkedAt: Date,
        latencyMilliseconds: Int?,
        errorSummary: String?
    ) {
        self.backend = backend
        self.auth = auth
        self.openaiCredential = openaiCredential
        self.sse = sse
        self.checkedAt = checkedAt
        self.latencyMilliseconds = latencyMilliseconds
        self.errorSummary = errorSummary
    }

    enum CodingKeys: String, CodingKey {
        case backend
        case auth
        case openaiCredential
        case sse
        case checkedAt
        case latencyMilliseconds
        case errorSummary
    }
}
