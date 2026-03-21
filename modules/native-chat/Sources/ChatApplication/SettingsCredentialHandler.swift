import ChatDomain
import ChatPersistenceCore

/// Handler protocol for API key credential operations used by the settings scene.
@MainActor
package protocol SettingsCredentialHandler {
    /// Loads the stored API key, returning `nil` if none exists.
    func loadAPIKey() -> String?
    /// Persists the given API key.
    func saveAPIKey(_ apiKey: String) throws(PersistenceError)
    /// Removes the stored API key.
    func clearAPIKey()
    /// Validates the API key against the OpenAI API.
    func validateAPIKey(_ apiKey: String) async -> Bool
    /// Synchronously resolves the Cloudflare gateway health based on local state.
    func resolveCloudflareHealth(
        typedAPIKey: String,
        gatewayEnabled: Bool,
        configuration: SettingsCloudflareConfiguration
    ) -> CloudflareHealthStatus
    /// Performs an async health check against the Cloudflare gateway.
    func checkCloudflareHealth(
        typedAPIKey: String,
        gatewayEnabled: Bool,
        configuration: SettingsCloudflareConfiguration
    ) async -> CloudflareHealthStatus
}
