import ChatApplication
import ChatDomain
import Foundation
import Observation
import os

/// Observable credential state for the settings scene.
///
/// Owns API key editing, validation, and Cloudflare health transitions.
@Observable
@MainActor
public final class SettingsCredentialsStore {
    /// The current API key text entered by the user.
    public var apiKey: String
    /// Result of the most recent API key validation, or `nil` if not yet validated.
    public var isAPIKeyValid: Bool?
    /// Whether an API key validation request is in flight.
    public var isValidating = false
    /// Whether a save confirmation should be shown in the UI.
    public var saveConfirmation = false
    /// Current Cloudflare gateway health status.
    public var cloudflareHealthStatus: CloudflareHealthStatus
    /// Whether a Cloudflare health check is in progress.
    public var isCheckingCloudflareHealth = false
    /// The currently selected Cloudflare configuration mode.
    public var cloudflareConfigurationMode: CloudflareGatewayConfigurationMode
    /// The custom Cloudflare gateway base URL being edited.
    public var customCloudflareGatewayBaseURL: String
    /// The custom Cloudflare gateway token being edited.
    public var customCloudflareAIGToken: String

    static let logger = Logger(subsystem: "GlassGPT", category: "settings")
    let controller: SettingsSceneController
    let isCloudflareGatewayEnabled: @MainActor () -> Bool
    let logFailures: Bool

    /// Creates credential state with the stored API key and current gateway configuration.
    public init(
        apiKey: String,
        controller: SettingsSceneController,
        isCloudflareGatewayEnabled: @escaping @MainActor () -> Bool,
        logFailures: Bool = true
    ) {
        self.apiKey = apiKey
        self.controller = controller
        self.isCloudflareGatewayEnabled = isCloudflareGatewayEnabled
        self.logFailures = logFailures
        let cloudflareConfigurationMode = controller.loadCloudflareConfigurationMode()
        let customCloudflareGatewayBaseURL = controller.loadCustomCloudflareGatewayBaseURL()
        let customCloudflareAIGToken = controller.loadCustomCloudflareGatewayToken() ?? ""
        self.cloudflareConfigurationMode = cloudflareConfigurationMode
        self.customCloudflareGatewayBaseURL = customCloudflareGatewayBaseURL
        self.customCloudflareAIGToken = customCloudflareAIGToken
        let cloudflareConfiguration = SettingsCloudflareConfiguration(
            mode: cloudflareConfigurationMode,
            customGatewayBaseURL: customCloudflareGatewayBaseURL,
            customGatewayToken: customCloudflareAIGToken
        )
        cloudflareHealthStatus = controller.resolveCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: isCloudflareGatewayEnabled(),
            configuration: cloudflareConfiguration
        )
    }

    /// Trims and saves the current API key, updating save confirmation and Cloudflare health.
    public func saveAPIKey() {
        do {
            guard let outcome = try controller.saveAPIKey(
                apiKey,
                gatewayEnabled: isCloudflareGatewayEnabled(),
                cloudflareConfiguration: currentCloudflareConfiguration()
            ) else {
                return
            }

            apiKey = outcome.apiKey
            saveConfirmation = true
            if let cloudflareHealthStatus = outcome.cloudflareHealthStatus {
                self.cloudflareHealthStatus = cloudflareHealthStatus
            }
        } catch {
            if logFailures {
                Self.logger.error("Failed to save API key: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Clears the API key and resets validation state.
    public func clearAPIKey() {
        apiKey = ""
        isAPIKeyValid = nil
        cloudflareHealthStatus = controller.clearAPIKey(
            gatewayEnabled: isCloudflareGatewayEnabled(),
            cloudflareConfiguration: currentCloudflareConfiguration()
        )
    }

    /// Validates the current API key against the OpenAI API and updates ``isAPIKeyValid``.
    public func validateAPIKey() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            isAPIKeyValid = false
            return
        }

        isValidating = true
        isAPIKeyValid = await controller.validateAPIKey(trimmedKey)
        isValidating = false
    }
}
