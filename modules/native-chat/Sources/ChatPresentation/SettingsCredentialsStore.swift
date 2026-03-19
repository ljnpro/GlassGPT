import ChatApplication
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

    private static let logger = Logger(subsystem: "GlassGPT", category: "settings")
    private let controller: SettingsSceneController
    private let isCloudflareGatewayEnabled: @MainActor () -> Bool

    /// Creates credential state with the stored API key and current gateway configuration.
    public init(
        apiKey: String,
        controller: SettingsSceneController,
        isCloudflareGatewayEnabled: @escaping @MainActor () -> Bool
    ) {
        self.apiKey = apiKey
        self.controller = controller
        self.isCloudflareGatewayEnabled = isCloudflareGatewayEnabled
        cloudflareHealthStatus = controller.resolveCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: isCloudflareGatewayEnabled()
        )
    }

    /// Trims and saves the current API key, updating save confirmation and Cloudflare health.
    public func saveAPIKey() {
        do {
            guard let outcome = try controller.saveAPIKey(
                apiKey,
                gatewayEnabled: isCloudflareGatewayEnabled()
            ) else {
                return
            }

            apiKey = outcome.apiKey
            saveConfirmation = true
            if let cloudflareHealthStatus = outcome.cloudflareHealthStatus {
                self.cloudflareHealthStatus = cloudflareHealthStatus
            }
        } catch {
            Self.logger.error("Failed to save API key: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears the API key and resets validation state.
    public func clearAPIKey() {
        apiKey = ""
        isAPIKeyValid = nil
        cloudflareHealthStatus = controller.clearAPIKey(
            gatewayEnabled: isCloudflareGatewayEnabled()
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

    /// Performs a Cloudflare gateway health check and updates ``cloudflareHealthStatus``.
    public func checkCloudflareHealth() async {
        let gatewayEnabled = isCloudflareGatewayEnabled()
        guard gatewayEnabled else {
            cloudflareHealthStatus = .unknown
            isCheckingCloudflareHealth = false
            return
        }

        let localStatus = controller.resolveCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: gatewayEnabled
        )
        guard localStatus == .unknown else {
            cloudflareHealthStatus = localStatus
            isCheckingCloudflareHealth = false
            return
        }

        isCheckingCloudflareHealth = true
        cloudflareHealthStatus = .checking
        cloudflareHealthStatus = await controller.checkCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: gatewayEnabled
        )
        isCheckingCloudflareHealth = false
    }

    /// Recomputes local gateway health after the Cloudflare preference changes.
    public func handleCloudflareGatewayChange(_ enabled: Bool) {
        guard enabled else {
            cloudflareHealthStatus = .unknown
            isCheckingCloudflareHealth = false
            return
        }

        cloudflareHealthStatus = controller.resolveCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: enabled
        )
    }
}
