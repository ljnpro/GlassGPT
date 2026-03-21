import ChatPersistenceCore
import Foundation
import OpenAITransport

extension NativeChatCompositionRoot {
    func makeConfigurationProvider(
        settingsStore: SettingsStore,
        cloudflareTokenStore: PersistedAPIKeyStore,
        defaults: CloudflareRuntimeConfigurationDefaults
    ) -> DefaultOpenAIConfigurationProvider {
        let provider = DefaultOpenAIConfigurationProvider(
            directOpenAIBaseURL: DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL,
            cloudflareGatewayBaseURL: defaults.gatewayBaseURL,
            cloudflareAIGToken: defaults.gatewayToken,
            useCloudflareGateway: settingsStore.cloudflareGatewayEnabled
        )
        applyCloudflareConfiguration(
            to: provider,
            settingsStore: settingsStore,
            cloudflareTokenStore: cloudflareTokenStore,
            defaults: defaults
        )
        return provider
    }

    func makeCloudflareConfigurationDefaults() -> CloudflareRuntimeConfigurationDefaults {
        CloudflareRuntimeConfigurationDefaults(
            gatewayBaseURL: resolvedConfigurationValue(
                infoKey: "CloudflareGatewayBaseURL",
                environmentKey: "CLOUDFLARE_GATEWAY_BASE_URL",
                fallback: DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL
            ),
            gatewayToken: resolvedConfigurationValue(
                infoKey: "CloudflareAIGToken",
                environmentKey: "CLOUDFLARE_AIG_TOKEN",
                fallback: DefaultOpenAIConfigurationProvider.defaultCloudflareAIGToken
            )
        )
    }

    func applyCloudflareConfiguration(
        to provider: DefaultOpenAIConfigurationProvider,
        settingsStore: SettingsStore,
        cloudflareTokenStore: PersistedAPIKeyStore,
        defaults: CloudflareRuntimeConfigurationDefaults
    ) {
        let persistedCustomBaseURL = settingsStore.customCloudflareGatewayBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedCustomToken = cloudflareTokenStore.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasCompleteCustomConfiguration = !persistedCustomBaseURL.isEmpty && !persistedCustomToken.isEmpty

        switch settingsStore.cloudflareGatewayConfigurationMode {
        case .default:
            provider.cloudflareGatewayBaseURL = defaults.gatewayBaseURL
            provider.cloudflareAIGToken = defaults.gatewayToken
        case .custom:
            provider.cloudflareGatewayBaseURL = persistedCustomBaseURL
            provider.cloudflareAIGToken = persistedCustomToken
        }

        provider.useCloudflareGateway = settingsStore.cloudflareGatewayEnabled
            && (
                settingsStore.cloudflareGatewayConfigurationMode == .default
                || hasCompleteCustomConfiguration
            )
    }

    func resolvedConfigurationValue(
        infoKey: String,
        environmentKey: String,
        fallback: String
    ) -> String {
        if let infoValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
           !infoValue.isEmpty {
            return infoValue
        }

        if let environmentValue = ProcessInfo.processInfo.environment[environmentKey],
           !environmentValue.isEmpty {
            return environmentValue
        }

        return fallback
    }
}

struct CloudflareRuntimeConfigurationDefaults {
    let gatewayBaseURL: String
    let gatewayToken: String
}
