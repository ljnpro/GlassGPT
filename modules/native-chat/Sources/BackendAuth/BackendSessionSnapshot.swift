import BackendContracts
import Foundation

public struct BackendSessionSnapshot: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let deviceID: String
    public let user: UserDTO

    public var isExpired: Bool {
        expiresAt <= Date()
    }

    public var session: SessionDTO {
        SessionDTO(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            deviceID: deviceID,
            user: user
        )
    }

    public init(session: SessionDTO) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        expiresAt = session.expiresAt
        deviceID = session.deviceID
        user = session.user
    }
}
