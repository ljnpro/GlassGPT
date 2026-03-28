import BackendAuth
import BackendClient
import BackendContracts
import Foundation
import Observation

@Observable
@MainActor
public final class SettingsAccountStore {
    public private(set) var connectionStatus: ConnectionCheckDTO?
    public private(set) var isCheckingConnection = false
    public private(set) var isAuthenticating = false
    public private(set) var isSigningOut = false
    public private(set) var lastErrorMessage: String?

    private let sessionStore: BackendSessionStore
    private let client: any BackendRequesting
    private let signInAction: (@MainActor () async throws -> Void)?
    private let signOutAction: (@MainActor () async -> Void)?

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
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

    public var syncStatusState: HealthCheckStateDTO? {
        guard isSignedIn else {
            return .missing
        }
        guard let connectionStatus else {
            return nil
        }
        if connectionStatus.backend == .healthy,
           connectionStatus.auth == .healthy,
           connectionStatus.sse == .healthy {
            return .healthy
        }
        if connectionStatus.auth == .unauthorized {
            return .unauthorized
        }
        if connectionStatus.sse == .degraded || connectionStatus.backend == .degraded {
            return .degraded
        }
        if connectionStatus.backend == .unavailable || connectionStatus.sse == .unavailable {
            return .unavailable
        }
        return connectionStatus.auth
    }

    public var syncStatusText: String {
        guard isSignedIn else {
            return String(localized: "Not Available")
        }
        guard let connectionStatus else {
            return String(localized: "Ready to Verify")
        }
        if connectionStatus.backend == .healthy,
           connectionStatus.auth == .healthy,
           connectionStatus.sse == .healthy {
            return String(localized: "Realtime Sync Ready")
        }
        if connectionStatus.auth == .unauthorized {
            return String(localized: "Session Needs Refresh")
        }
        if connectionStatus.sse == .degraded || connectionStatus.backend == .degraded {
            return String(localized: "Available with Degraded Realtime")
        }
        if connectionStatus.backend == .unavailable || connectionStatus.sse == .unavailable {
            return String(localized: "Backend Unavailable")
        }
        return String(localized: "Needs Attention")
    }

    public var lastCheckedText: String? {
        guard let checkedAt = connectionStatus?.checkedAt else {
            return nil
        }
        return Self.relativeDateFormatter.localizedString(for: checkedAt, relativeTo: Date())
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
            lastErrorMessage = Self.describeSignInError(error)
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
            connectionStatus = ConnectionCheckDTO(
                backend: .unavailable,
                auth: sessionStore.isSignedIn ? .unauthorized : .missing,
                openaiCredential: .missing,
                sse: .unavailable,
                checkedAt: Date(),
                latencyMilliseconds: nil,
                errorSummary: error.localizedDescription
            )
        }
    }

    private static func describeSignInError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain != NSCocoaErrorDomain else {
            return error.localizedDescription
        }

        return "\(error.localizedDescription) [\(nsError.domain):\(nsError.code)]"
    }
}
