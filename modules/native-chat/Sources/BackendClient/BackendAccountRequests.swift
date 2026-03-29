import BackendContracts
import Foundation

@MainActor
public extension BackendClient {
    func fetchCurrentUser() async throws -> UserDTO {
        try await performWithRetry(
            path: "/v1/me",
            method: "GET",
            body: String?.none,
            authorizationMode: .required,
            responseType: UserDTO.self
        )
    }

    func connectionCheck() async throws -> ConnectionCheckDTO {
        try await performWithRetry(
            path: "/v1/connection/check",
            method: "GET",
            body: String?.none,
            authorizationMode: sessionStore.isSignedIn ? .ifAvailable : .none,
            responseType: ConnectionCheckDTO.self
        )
    }
}
