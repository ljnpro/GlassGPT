import Foundation

/// A backend user profile.
public struct UserDTO: Codable, Equatable, Sendable {
    public let id: String
    public let appleSubject: String
    public let displayName: String?
    public let email: String?
    public let createdAt: Date

    /// Creates a user DTO with the given identity fields.
    public init(
        id: String,
        appleSubject: String,
        displayName: String?,
        email: String?,
        createdAt: Date
    ) {
        self.id = id
        self.appleSubject = appleSubject
        self.displayName = displayName
        self.email = email
        self.createdAt = createdAt
    }
}

/// An authenticated session containing access and refresh tokens.
public struct SessionDTO: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let deviceID: String
    public let user: UserDTO

    /// Creates a session DTO with the given authentication fields.
    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        deviceID: String,
        user: UserDTO
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.deviceID = deviceID
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
        case deviceID = "deviceId"
        case user
    }
}

/// The validation state of a stored credential.
public enum CredentialStatusStateDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case missing
    case valid
    case invalid
}

/// The status of an external provider credential stored on the backend.
public struct CredentialStatusDTO: Codable, Equatable, Sendable {
    public let provider: String
    public let state: CredentialStatusStateDTO
    public let checkedAt: Date?
    public let lastErrorSummary: String?

    /// Creates a credential status with the given validation state.
    public init(
        provider: String,
        state: CredentialStatusStateDTO,
        checkedAt: Date?,
        lastErrorSummary: String?
    ) {
        self.provider = provider
        self.state = state
        self.checkedAt = checkedAt
        self.lastErrorSummary = lastErrorSummary
    }
}

/// Request body sent to the backend to exchange an Apple identity token for a session.
public struct AppleAuthRequestDTO: Codable, Equatable, Sendable {
    public let identityToken: String
    public let authorizationCode: String?
    public let deviceID: String
    public let email: String?
    public let givenName: String?
    public let familyName: String?

    /// Creates an Apple auth request with the given token and user information.
    public init(
        identityToken: String,
        authorizationCode: String?,
        deviceID: String,
        email: String?,
        givenName: String?,
        familyName: String?
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.deviceID = deviceID
        self.email = email
        self.givenName = givenName
        self.familyName = familyName
    }

    enum CodingKeys: String, CodingKey {
        case identityToken
        case authorizationCode
        case deviceID = "deviceId"
        case email
        case givenName
        case familyName
    }
}

/// Request body for refreshing an expired session using a refresh token.
public struct RefreshSessionRequestDTO: Codable, Equatable, Sendable {
    public let refreshToken: String

    /// Creates a refresh request with the given token.
    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}

/// Request body for storing an OpenAI API key on the backend.
public struct OpenAICredentialRequestDTO: Codable, Equatable, Sendable {
    public let apiKey: String

    /// Creates a credential request wrapping the given API key.
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}
