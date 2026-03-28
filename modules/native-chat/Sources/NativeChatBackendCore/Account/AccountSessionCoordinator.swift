import BackendAuth
import BackendClient
import ChatPersistenceCore
import ConversationSyncApplication
import Foundation

@MainActor
package final class AccountSessionCoordinator {
    private let appleSignInCoordinator: AppleSignInCoordinator
    private let deviceIdentityStore: BackendDeviceIdentityStore
    private let client: BackendClient
    private let loader: BackendConversationLoader
    private let sessionStore: BackendSessionStore
    private let reloadProjectionSurfaces: @MainActor () async -> Void
    private let resetProjectionSurfaces: @MainActor () -> Void
    private let refreshHistory: @MainActor () -> Void

    init(
        appleSignInCoordinator: AppleSignInCoordinator,
        deviceIdentityStore: BackendDeviceIdentityStore,
        client: BackendClient,
        loader: BackendConversationLoader,
        sessionStore: BackendSessionStore,
        reloadProjectionSurfaces: @escaping @MainActor () async -> Void,
        resetProjectionSurfaces: @escaping @MainActor () -> Void,
        refreshHistory: @escaping @MainActor () -> Void
    ) {
        self.appleSignInCoordinator = appleSignInCoordinator
        self.deviceIdentityStore = deviceIdentityStore
        self.client = client
        self.loader = loader
        self.sessionStore = sessionStore
        self.reloadProjectionSurfaces = reloadProjectionSurfaces
        self.resetProjectionSurfaces = resetProjectionSurfaces
        self.refreshHistory = refreshHistory
    }

    func signIn() async {
        do {
            let payload = try await appleSignInCoordinator.signIn()
            _ = try await client.authenticateWithApple(
                payload,
                deviceID: deviceIdentityStore.deviceID
            )
            await reloadProjectionSurfaces()
            refreshHistory()
        } catch {
            Loggers.app.error("[AccountSessionCoordinator.signIn] \(error.localizedDescription)")
        }
    }

    func signOut() async {
        let accountID = sessionStore.currentUser?.id

        do {
            try await client.logout()
        } catch {
            Loggers.app.error("[AccountSessionCoordinator.signOut] \(error.localizedDescription)")
        }

        sessionStore.clear()

        if let accountID {
            do {
                try loader.clearAccountCache(accountID: accountID)
            } catch {
                Loggers.persistence.error("[AccountSessionCoordinator.clearAccountCache] \(error.localizedDescription)")
            }
        }

        resetProjectionSurfaces()
        refreshHistory()
    }
}
