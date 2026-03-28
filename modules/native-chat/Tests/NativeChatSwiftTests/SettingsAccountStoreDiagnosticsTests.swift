import BackendAuth
import BackendClient
import BackendContracts
import ChatPresentation
import Foundation
import Testing

@Suite(.tags(.presentation))
@MainActor
struct SettingsAccountStoreDiagnosticsTests {
    @Test func `sign-in flow error exposes stage label and underlying error`() {
        let appleError = SignInFlowError.appleAuthorization(underlying: URLError(.timedOut))
        #expect(appleError.stageLabel == "apple-auth")
        #expect((appleError.underlyingError as? URLError)?.code == .timedOut)

        let backendError = SignInFlowError.backendAuthentication(underlying: URLError(.notConnectedToInternet))
        #expect(backendError.stageLabel == "backend-auth")
        #expect((backendError.underlyingError as? URLError)?.code == .notConnectedToInternet)
    }

    @Test func `settings account store distinguishes apple auth and backend auth failures`() async {
        let sessionStore = BackendSessionStore()
        let client = SettingsAccountDiagnosticsBackendRequester()

        let appleFailure = SettingsAccountStore(
            sessionStore: sessionStore,
            client: client,
            signInAction: {
                throw SignInFlowError.appleAuthorization(underlying: URLError(.timedOut))
            }
        )
        await appleFailure.signIn()
        #expect(appleFailure.lastErrorMessage?.contains("Apple authorization failed before backend sign-in.") == true)
        #expect(appleFailure.lastErrorMessage?.contains("[NSURLErrorDomain:-1001]") == true)

        let backendFailure = SettingsAccountStore(
            sessionStore: sessionStore,
            client: client,
            signInAction: {
                throw SignInFlowError.backendAuthentication(underlying: URLError(.timedOut))
            }
        )
        await backendFailure.signIn()
        #expect(backendFailure.lastErrorMessage?.contains("Backend sign-in failed after Apple authorization.") == true)
        #expect(backendFailure.lastErrorMessage?.contains("[NSURLErrorDomain:-1001]") == true)
    }
}

@MainActor
private final class SettingsAccountDiagnosticsBackendRequester: BackendRequesting {
    func cancelRun(_: String) async throws -> RunSummaryDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func createConversation(
        title _: String,
        mode _: ConversationModeDTO
    ) async throws -> ConversationDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func fetchConversationDetail(_: String) async throws -> ConversationDetailDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func fetchConversations() async throws -> [ConversationDTO] {
        throw DiagnosticsTestError.unimplemented
    }

    func fetchCurrentUser() async throws -> UserDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func fetchRun(_: String) async throws -> RunSummaryDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func connectionCheck() async throws -> ConnectionCheckDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func authenticateWithApple(
        _: AppleSignInPayload,
        deviceID _: String
    ) async throws -> SessionDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func refreshSession() async throws -> SessionDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func retryRun(_: String) async throws -> RunSummaryDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func sendMessage(_: String, to _: String) async throws -> RunSummaryDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func startAgentRun(prompt _: String?, in _: String) async throws -> RunSummaryDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func streamRun(_ runID: String) -> BackendSSEStream {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "localhost"
        components.path = "/v1/runs/\(runID)/stream"
        let url = components.url ?? URL(fileURLWithPath: "/")
        return BackendSSEStream(url: url, urlSession: .shared, authorizationHeader: nil)
    }

    func syncEvents(after _: String?) async throws -> SyncEnvelopeDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func logout() async throws {}
    func storeOpenAIKey(_: String) async throws -> CredentialStatusDTO {
        throw DiagnosticsTestError.unimplemented
    }

    func deleteOpenAIKey() async throws {}
}

private enum DiagnosticsTestError: Error {
    case unimplemented
}
