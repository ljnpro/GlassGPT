import Foundation

public struct AppleSignInPayload: Equatable, Sendable {
    public let userIdentifier: String
    public let identityToken: String
    public let authorizationCode: String?
    public let email: String?
    public let givenName: String?
    public let familyName: String?

    public init(
        userIdentifier: String,
        identityToken: String,
        authorizationCode: String?,
        email: String?,
        givenName: String?,
        familyName: String?
    ) {
        self.userIdentifier = userIdentifier
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.email = email
        self.givenName = givenName
        self.familyName = familyName
    }
}
