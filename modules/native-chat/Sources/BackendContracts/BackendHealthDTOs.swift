import Foundation

/// The health state of an individual backend subsystem.
public enum HealthCheckStateDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case healthy
    case degraded
    case unavailable
    case missing
    case invalid
    case unauthorized
}

/// Whether the current app version is compatible with the backend.
public enum AppCompatibilityDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case compatible
    case updateRequired = "update_required"
}

/// Aggregated health check result for all backend subsystems.
public struct ConnectionCheckDTO: Codable, Equatable, Sendable {
    public let backend: HealthCheckStateDTO
    public let auth: HealthCheckStateDTO
    public let openaiCredential: HealthCheckStateDTO
    public let sse: HealthCheckStateDTO
    public let checkedAt: Date
    public let latencyMilliseconds: Int?
    public let errorSummary: String?
    public let backendVersion: String
    public let minimumSupportedAppVersion: String
    public let appCompatibility: AppCompatibilityDTO

    /// Creates a connection check result with the given subsystem states.
    public init(
        backend: HealthCheckStateDTO,
        auth: HealthCheckStateDTO,
        openaiCredential: HealthCheckStateDTO,
        sse: HealthCheckStateDTO,
        checkedAt: Date,
        latencyMilliseconds: Int?,
        errorSummary: String?,
        backendVersion: String = "5.5.0",
        minimumSupportedAppVersion: String = "5.4.0",
        appCompatibility: AppCompatibilityDTO = .compatible
    ) {
        self.backend = backend
        self.auth = auth
        self.openaiCredential = openaiCredential
        self.sse = sse
        self.checkedAt = checkedAt
        self.latencyMilliseconds = latencyMilliseconds
        self.errorSummary = errorSummary
        self.backendVersion = backendVersion
        self.minimumSupportedAppVersion = minimumSupportedAppVersion
        self.appCompatibility = appCompatibility
    }

    enum CodingKeys: String, CodingKey {
        case backend
        case auth
        case openaiCredential
        case sse
        case checkedAt
        case latencyMilliseconds
        case errorSummary
        case backendVersion
        case minimumSupportedAppVersion
        case appCompatibility
    }
}
