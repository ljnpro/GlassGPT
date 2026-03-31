import BackendAuth
import BackendContracts
import ChatPresentation
import Foundation
import Testing

@Suite(.tags(.presentation))
@MainActor
struct SettingsAccountStoreCompatibilityTests {
    @Test
    func `settings account store surfaces update required as a blocking sync state`() async {
        let sessionStore = BackendSessionStore(session: TestFixtures.session())
        let client = PresentationBackendRequester()
        let store = SettingsAccountStore(sessionStore: sessionStore, client: client)

        client.connectionCheckResult = .success(
            ConnectionCheckDTO(
                backend: .healthy,
                auth: .healthy,
                openaiCredential: .healthy,
                sse: .healthy,
                checkedAt: .now,
                latencyMilliseconds: nil,
                errorSummary: nil,
                backendVersion: "5.6.0",
                minimumSupportedAppVersion: "5.4.0",
                appCompatibility: .updateRequired
            )
        )

        await store.checkConnection()

        #expect(store.syncStatusState == .invalid)
        #expect(store.syncStatusText == "App Update Required")
        #expect(store.syncStatusDetailText == "Install GlassGPT 5.4.0 or newer.")
        #expect(
            store.compatibilityMessage
                == "Backend 5.6.0 requires app version 5.4.0 or newer."
        )
    }
}
