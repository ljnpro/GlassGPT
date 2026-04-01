import BackendAuth
import BackendClient
import BackendContracts
import Foundation
import Observation

@Observable
@MainActor
public final class SettingsAccountStore {
    static let authRuntimeConfigurationErrorSummary = "auth_runtime_configuration_missing"

    public private(set) var connectionStatus: ConnectionCheckDTO?
    public private(set) var isCheckingConnection = false
    public private(set) var isAuthenticating = false
    public private(set) var isSigningOut = false
    public private(set) var lastErrorMessage: String?

    private let sessionStore: BackendSessionStore
    private let client: any BackendRequesting
    private let signInAction: (@MainActor () async throws -> Void)?
    private let signOutAction: (@MainActor () async -> Void)?

    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Creates the Settings account store that projects sign-in, sync, and connection-check state.
    public init(
        sessionStore: BackendSessionStore,
        client: any BackendRequesting,
        signInAction: (@MainActor () async throws -> Void)? = nil,
        signOutAction: (@MainActor () async -> Void)? = nil
    ) {
        self.sessionStore = sessionStore
        self.client = client
        self.signInAction = signInAction
        self.signOutAction = signOutAction
    }

    public var isSignedIn: Bool {
        sessionStore.isSignedIn
    }

    public var displayName: String {
        sessionStore.currentUser?.displayName
            ?? sessionStore.currentUser?.email
            ?? String(localized: "Not Signed In")
    }

    public var subtitle: String {
        if let email = sessionStore.currentUser?.email, !email.isEmpty {
            return email
        }
        if let appleSubject = sessionStore.currentUser?.appleSubject, !appleSubject.isEmpty {
            return appleSubject
        }
        return String(localized: "Sign in with Apple to enable sync.")
    }

    public var sessionStatusState: HealthCheckStateDTO {
        isSignedIn ? .healthy : .missing
    }

    public var sessionStatusText: String {
        isSignedIn ? String(localized: "Active") : String(localized: "Sign In Required")
    }

    /// Starts Sign in with Apple and refreshes the visible account state after authentication completes.
    public func signIn() async {
        guard let signInAction, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await signInAction()
            lastErrorMessage = nil
        } catch is CancellationError {
            lastErrorMessage = nil
        } catch {
            let fallbackMessage = Self.describeSignInError(error)
            if let diagnosticMessage = await diagnoseBackendAuthenticationFailure(error) {
                lastErrorMessage = diagnosticMessage
            } else {
                lastErrorMessage = fallbackMessage
            }
        }
    }

    /// Signs out the current account and clears the last observed connection status snapshot.
    public func signOut() async {
        guard let signOutAction, !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await signOutAction()
        connectionStatus = nil
        lastErrorMessage = nil
    }

    /// Runs the backend connection check and projects the combined health result into Settings state.
    public func checkConnection() async {
        isCheckingConnection = true
        defer { isCheckingConnection = false }

        do {
            connectionStatus = try await client.connectionCheck()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            connectionStatus = nil
        }
    }

    private static func describeSignInError(_ error: Error) -> String {
        if let signInFlowError = error as? SignInFlowError {
            let nsError = signInFlowError.underlyingError as NSError
            return "\(signInFlowError.localizedDescription) [\(nsError.domain):\(nsError.code)]"
        }

        let nsError = error as NSError
        guard nsError.domain != NSCocoaErrorDomain else {
            return error.localizedDescription
        }

        return "\(error.localizedDescription) [\(nsError.domain):\(nsError.code)]"
    }

    private func diagnoseBackendAuthenticationFailure(_ error: Error) async -> String? {
        guard Self.shouldDiagnoseBackendAuthenticationFailure(error) else {
            return nil
        }

        do {
            let status = try await client.connectionCheck()
            connectionStatus = status
            return Self.backendAuthenticationDiagnosticMessage(for: status)
        } catch {
            return nil
        }
    }

    private static func shouldDiagnoseBackendAuthenticationFailure(_ error: Error) -> Bool {
        guard let signInFlowError = error as? SignInFlowError,
              signInFlowError.stageLabel == "backend-auth",
              let backendError = signInFlowError.underlyingError as? BackendAPIError else {
            return false
        }

        return backendError == .serverError || backendError == .serviceUnavailable
    }

    private static func backendAuthenticationDiagnosticMessage(
        for status: ConnectionCheckDTO
    ) -> String? {
        guard status.errorSummary == authRuntimeConfigurationErrorSummary else {
            return nil
        }

        return String(
            localized: "Apple sign-in succeeded, but backend authentication is temporarily unavailable."
        )
    }
}
