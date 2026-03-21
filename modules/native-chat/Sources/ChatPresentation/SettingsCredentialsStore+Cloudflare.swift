import ChatApplication
import ChatDomain
import Foundation

@MainActor
extension SettingsCredentialsStore {
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
            gatewayEnabled: gatewayEnabled,
            configuration: currentCloudflareConfiguration()
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
            gatewayEnabled: gatewayEnabled,
            configuration: currentCloudflareConfiguration()
        )
        isCheckingCloudflareHealth = false
    }

    /// Switches the locally selected Cloudflare configuration mode.
    public func setCloudflareConfigurationMode(_ mode: CloudflareGatewayConfigurationMode) {
        cloudflareConfigurationMode = mode
        if mode == .default {
            controller.persistCloudflareConfigurationMode(.default)
        }
        refreshCloudflareHealthStatus()
    }

    /// Saves the currently edited custom Cloudflare gateway configuration and activates it.
    public func saveCustomCloudflareConfiguration() {
        let trimmedGatewayBaseURL = customCloudflareGatewayBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGatewayToken = customCloudflareAIGToken
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try controller.saveCustomCloudflareConfiguration(
                gatewayBaseURL: trimmedGatewayBaseURL,
                gatewayToken: trimmedGatewayToken
            )
            cloudflareConfigurationMode = .custom
            customCloudflareGatewayBaseURL = trimmedGatewayBaseURL
            customCloudflareAIGToken = trimmedGatewayToken
            refreshCloudflareHealthStatus()
        } catch {
            if logFailures {
                Self.logger.error(
                    "Failed to save custom Cloudflare configuration: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Clears the saved custom Cloudflare gateway configuration while keeping custom mode active.
    public func clearCustomCloudflareConfiguration() {
        controller.clearCustomCloudflareConfiguration()
        customCloudflareGatewayBaseURL = ""
        customCloudflareAIGToken = ""
        refreshCloudflareHealthStatus()
    }

    /// Recomputes local gateway health after the Cloudflare preference changes.
    public func handleCloudflareGatewayChange(_ enabled: Bool) {
        guard enabled else {
            cloudflareHealthStatus = .unknown
            isCheckingCloudflareHealth = false
            return
        }

        refreshCloudflareHealthStatus()
    }

    /// Recomputes local gateway health for the current configuration preview.
    public func refreshCloudflareHealthStatus() {
        let gatewayEnabled = isCloudflareGatewayEnabled()
        guard gatewayEnabled else {
            cloudflareHealthStatus = .unknown
            isCheckingCloudflareHealth = false
            return
        }

        cloudflareHealthStatus = controller.resolveCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: gatewayEnabled,
            configuration: currentCloudflareConfiguration()
        )
    }

    func currentCloudflareConfiguration(
        mode: CloudflareGatewayConfigurationMode? = nil,
        customGatewayBaseURL: String? = nil,
        customGatewayToken: String? = nil
    ) -> SettingsCloudflareConfiguration {
        SettingsCloudflareConfiguration(
            mode: mode ?? cloudflareConfigurationMode,
            customGatewayBaseURL: customGatewayBaseURL ?? customCloudflareGatewayBaseURL,
            customGatewayToken: customGatewayToken ?? customCloudflareAIGToken
        )
    }
}
