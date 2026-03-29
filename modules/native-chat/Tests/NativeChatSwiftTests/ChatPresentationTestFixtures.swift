import BackendContracts
import Foundation

enum TestFixtures {
    static func session(
        displayName: String? = "Taylor",
        email: String? = "taylor@example.com"
    ) -> SessionDTO {
        SessionDTO(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: .init(timeIntervalSince1970: 4000),
            deviceID: "device-1",
            user: UserDTO(
                id: "user-1",
                appleSubject: "apple-user",
                displayName: displayName,
                email: email,
                createdAt: .init(timeIntervalSince1970: 1)
            )
        )
    }
}
