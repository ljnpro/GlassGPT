import BackendContracts
import Foundation

@MainActor
extension BackendClient {
    func refreshSessionIfNeeded(for authorizationMode: AuthorizationMode) async throws {
        guard authorizationMode.requiresAuthorization else {
            return
        }

        guard let session = sessionStore.loadSession() else {
            if authorizationMode == .required {
                throw BackendAPIError.unauthorized
            }
            return
        }

        let refreshLeadTime: TimeInterval = 60
        guard session.expiresAt.timeIntervalSinceNow <= refreshLeadTime else {
            return
        }

        BackendNetworkLogger.logAuth("[Session] proactive token refresh (expires in \(Int(session.expiresAt.timeIntervalSinceNow))s)")
        do {
            try await refreshSessionWithStoredRefreshToken()
        } catch {
            BackendNetworkLogger.logAuthError("[Session] proactive refresh failed: \(error.localizedDescription)")
            if authorizationMode == .required {
                throw error
            }
        }
    }

    func refreshSessionWithStoredRefreshToken() async throws {
        guard let currentSession = sessionStore.loadSession() else {
            BackendNetworkLogger.logAuthError("[Session] refresh attempted with no stored session")
            throw BackendAPIError.unauthorized
        }

        BackendNetworkLogger.logAuth("[Session] refreshing access token")
        do {
            let (data, response) = try await execute(
                path: "/v1/auth/refresh",
                method: "POST",
                body: RefreshSessionRequestDTO(refreshToken: currentSession.refreshToken),
                authorizationMode: .none,
                queryItems: [],
                allowRefreshRetry: false
            )
            guard (200 ..< 300).contains(response.statusCode) else {
                throw BackendAPIError.invalidResponse
            }
            let session = try JSONDecoder.backend.decode(SessionDTO.self, from: data)
            sessionStore.replace(session: session)
            BackendNetworkLogger.logAuth("[Session] token refresh succeeded")
        } catch {
            BackendNetworkLogger.logAuthError("[Session] token refresh failed, clearing session: \(error.localizedDescription)")
            sessionStore.clear()
            throw error
        }
    }
}
