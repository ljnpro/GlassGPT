import Foundation

public struct UserDTO: Codable, Equatable, Sendable {
    public let id: String
    public let appleSubject: String
    public let displayName: String?
    public let email: String?
    public let createdAt: Date

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

public struct SessionDTO: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let deviceID: String
    public let user: UserDTO

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

public enum CredentialStatusStateDTO: String, Codable, Equatable, Sendable, CaseIterable {
    case missing
    case valid
    case invalid
}

public struct CredentialStatusDTO: Codable, Equatable, Sendable {
    public let provider: String
    public let state: CredentialStatusStateDTO
    public let checkedAt: Date?
    public let lastErrorSummary: String?

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

public struct AppleAuthRequestDTO: Codable, Equatable, Sendable {
    public let identityToken: String
    public let authorizationCode: String?
    public let deviceID: String
    public let email: String?
    public let givenName: String?
    public let familyName: String?

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

public struct RefreshSessionRequestDTO: Codable, Equatable, Sendable {
    public let refreshToken: String

    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}

public struct OpenAICredentialRequestDTO: Codable, Equatable, Sendable {
    public let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}
