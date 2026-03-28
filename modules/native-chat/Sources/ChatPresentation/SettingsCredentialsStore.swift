import BackendAuth
import BackendClient
import BackendContracts
import Foundation
import Observation

/// Observable OpenAI credential state for the backend-owned settings flow.
@Observable
@MainActor
public final class SettingsCredentialsStore {
    public var apiKey: String
    public var saveConfirmation = false
    public private(set) var credentialStatus: CredentialStatusDTO?
    public private(set) var isSaving = false
    public private(set) var isDeleting = false
    public private(set) var isRefreshingStatus = false
    public private(set) var lastErrorMessage: String?

    private let client: any BackendRequesting
    private let sessionStore: BackendSessionStore

    /// Creates the backend-owned OpenAI credential state store used by Settings.
    public init(
        client: any BackendRequesting,
        sessionStore: BackendSessionStore
    ) {
        apiKey = ""
        self.client = client
        self.sessionStore = sessionStore
    }

    public var isSignedIn: Bool {
        sessionStore.isSignedIn
    }

    public var statusLabel: String {
        guard let credentialStatus else {
            return isSignedIn
                ? String(localized: "Status unknown. Use Check Connection to refresh.")
                : String(localized: "Sign in to manage your OpenAI API key.")
        }

        switch credentialStatus.state {
        case .missing:
            return String(localized: "No OpenAI API key is stored on the backend.")
        case .valid:
            return String(localized: "Your OpenAI API key is stored and valid.")
        case .invalid:
            if let lastErrorSummary = credentialStatus.lastErrorSummary, !lastErrorSummary.isEmpty {
                return lastErrorSummary
            }
            return String(localized: "The stored OpenAI API key is invalid.")
        }
    }

    /// Refreshes the visible credential state by asking the backend for the latest connection summary.
    public func refreshStatus() async {
        guard sessionStore.isSignedIn else {
            credentialStatus = nil
            lastErrorMessage = nil
            return
        }

        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        do {
            let status = try await client.connectionCheck()
            credentialStatus = CredentialStatusDTO(
                provider: "openai",
                state: Self.mapCredentialState(status.openaiCredential),
                checkedAt: status.checkedAt,
                lastErrorSummary: status.errorSummary
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Uploads the currently entered OpenAI API key for encrypted backend storage.
    public func saveAPIKey() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, sessionStore.isSignedIn else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            credentialStatus = try await client.storeOpenAIKey(trimmedKey)
            apiKey = ""
            saveConfirmation = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Deletes the stored OpenAI API key for the signed-in account.
    public func deleteAPIKey() async {
        guard sessionStore.isSignedIn else {
            return
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await client.deleteOpenAIKey()
            credentialStatus = CredentialStatusDTO(
                provider: "openai",
                state: .missing,
                checkedAt: Date(),
                lastErrorSummary: nil
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private static func mapCredentialState(_ state: HealthCheckStateDTO) -> CredentialStatusStateDTO {
        switch state {
        case .healthy, .degraded:
            .valid
        case .invalid:
            .invalid
        case .missing, .unavailable, .unauthorized:
            .missing
        }
    }
}
