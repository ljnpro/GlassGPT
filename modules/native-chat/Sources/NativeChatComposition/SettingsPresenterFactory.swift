import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import GeneratedFilesInfra
import OpenAITransport
import Foundation
import UIKit

@MainActor
/// Assembles a ``SettingsPresenter`` wired to the given stores, services, and transport layer.
// swiftlint:disable:next function_body_length — composition root wires many dependencies
package func makeSettingsPresenter(
    settingsStore: SettingsStore,
    apiKeyStore: PersistedAPIKeyStore,
    openAIService: OpenAIService,
    requestBuilder: OpenAIRequestBuilder,
    transport: OpenAIDataTransport,
    configurationProvider: OpenAIConfigurationProvider,
    fileDownloadService: GeneratedFilesInfra.FileDownloadService,
    appVersionString: String? = nil,
    platformString: String? = nil
) -> SettingsPresenter {
    var mutableConfigurationProvider = configurationProvider
    let isValidGatewayModelsURL: (String) -> Bool = { baseURL in
        guard let url = URL(string: "\(baseURL)/models"),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return false
        }
        return true
    }
    // swiftlint:disable:next line_length
    let resolvedCloudflareHealth: (_ typedAPIKey: String, _ gatewayEnabled: Bool) -> CloudflareHealthStatus = { typedAPIKey, gatewayEnabled in
        guard gatewayEnabled else {
            return .unknown
        }

        let gatewayBaseURL = mutableConfigurationProvider.cloudflareGatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gatewayBaseURL.isEmpty else {
            return .gatewayUnavailable
        }

        let gatewayToken = mutableConfigurationProvider.cloudflareAIGToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gatewayToken.isEmpty else {
            return .gatewayUnavailable
        }

        guard isValidGatewayModelsURL(gatewayBaseURL) else {
            return .invalidGatewayURL
        }

        let typedKey = typedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedKey = apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedAPIKey = typedKey.isEmpty ? storedKey : typedKey

        guard !resolvedAPIKey.isEmpty else {
            return .missingAPIKey
        }

        return .unknown
    }

    let credentialHandler = SettingsCredentialHandlerImpl(
        apiKeyStore: apiKeyStore,
        openAIService: openAIService,
        requestBuilder: requestBuilder,
        transport: transport,
        resolvedCloudflareHealth: resolvedCloudflareHealth,
        loadConfigurationProvider: { mutableConfigurationProvider }
    )

    let cacheHandler = SettingsCacheHandlerImpl(
        fileDownloadService: fileDownloadService
    )

    let persistenceHandler = SettingsPersistenceHandlerImpl(
        settingsStore: settingsStore,
        applyCloudflareEnabled: { enabled in
            mutableConfigurationProvider.useCloudflareGateway = enabled
        }
    )

    let controller = SettingsSceneController(
        credentialHandler: credentialHandler,
        cacheHandler: cacheHandler,
        persistenceHandler: persistenceHandler
    )

    return SettingsPresenter(
        apiKey: apiKeyStore.loadAPIKey() ?? "",
        defaultModel: settingsStore.defaultModel,
        defaultEffort: settingsStore.defaultEffort,
        defaultBackgroundModeEnabled: settingsStore.defaultBackgroundModeEnabled,
        defaultServiceTier: settingsStore.defaultServiceTier,
        appTheme: settingsStore.appTheme,
        hapticEnabled: settingsStore.hapticEnabled,
        cloudflareEnabled: settingsStore.cloudflareGatewayEnabled,
        appVersionString: appVersionString ?? resolvedAppVersionString(),
        platformString: platformString ?? resolvedPlatformString(),
        generatedImageCacheLimitString: SettingsPresenter.byteCountFormatter.string(
            fromByteCount: GeneratedFilesInfra.FileDownloadService.generatedImageCacheLimitBytes
        ),
        generatedDocumentCacheLimitString: SettingsPresenter.byteCountFormatter.string(
            fromByteCount: GeneratedFilesInfra.FileDownloadService.generatedDocumentCacheLimitBytes
        ),
        controller: controller
    )
}

// MARK: - Handler Implementations

@MainActor
private struct SettingsCredentialHandlerImpl: SettingsCredentialHandler {
    let apiKeyStore: PersistedAPIKeyStore
    let openAIService: OpenAIService
    let requestBuilder: OpenAIRequestBuilder
    let transport: OpenAIDataTransport
    let resolvedCloudflareHealth: (_ typedAPIKey: String, _ gatewayEnabled: Bool) -> CloudflareHealthStatus
    let loadConfigurationProvider: () -> OpenAIConfigurationProvider

    func loadAPIKey() -> String? {
        apiKeyStore.loadAPIKey()
    }

    func saveAPIKey(_ apiKey: String) throws(PersistenceError) {
        try apiKeyStore.saveAPIKey(apiKey)
    }

    func clearAPIKey() {
        apiKeyStore.deleteAPIKey()
    }

    func validateAPIKey(_ apiKey: String) async -> Bool {
        await openAIService.validateAPIKey(apiKey)
    }

    func resolveCloudflareHealth(typedAPIKey: String, gatewayEnabled: Bool) -> CloudflareHealthStatus {
        resolvedCloudflareHealth(typedAPIKey, gatewayEnabled)
    }

    func checkCloudflareHealth(typedAPIKey: String, gatewayEnabled: Bool) async -> CloudflareHealthStatus {
        let localStatus = resolvedCloudflareHealth(typedAPIKey, gatewayEnabled)
        guard localStatus == .unknown else {
            return localStatus
        }

        let trimmedKey = typedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : typedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let gatewayRequest: URLRequest
        do {
            gatewayRequest = try requestBuilder.modelsRequest(apiKey: trimmedKey)
        } catch {
            return .invalidGatewayURL
        }

        let configProvider = loadConfigurationProvider()
        var request = gatewayRequest
        request.url = URL(string: "\(configProvider.cloudflareGatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))/models")

        do {
            let (data, response) = try await transport.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .remoteError("Invalid gateway response")
            }

            if (200...299).contains(httpResponse.statusCode) {
                return .connected
            }

            do {
                let payload = try JSONCoding.decode(SettingsErrorResponseDTO.self, from: data)
                if let message = payload.message ?? payload.error?.message,
                   !message.isEmpty {
                    return .remoteError(message)
                }
            } catch {
                Loggers.settings.debug("Cloudflare error response JSON parsing failed: \(error.localizedDescription)")
            }

            return .remoteError(String(data: data, encoding: .utf8) ?? "Status \(httpResponse.statusCode)")
        } catch {
            return .remoteError(error.localizedDescription)
        }
    }
}

@MainActor
private struct SettingsCacheHandlerImpl: SettingsCacheHandler {
    let fileDownloadService: GeneratedFilesInfra.FileDownloadService

    func refreshGeneratedImageCacheSize() async -> Int64 {
        await fileDownloadService.generatedImageCacheSize()
    }

    func refreshGeneratedDocumentCacheSize() async -> Int64 {
        await fileDownloadService.generatedDocumentCacheSize()
    }

    func clearGeneratedImageCache() async -> Int64 {
        await fileDownloadService.clearGeneratedImageCache()
        return await fileDownloadService.generatedImageCacheSize()
    }

    func clearGeneratedDocumentCache() async -> Int64 {
        await fileDownloadService.clearGeneratedDocumentCache()
        return await fileDownloadService.generatedDocumentCacheSize()
    }
}

@MainActor
private struct SettingsPersistenceHandlerImpl: SettingsPersistenceHandler {
    let settingsStore: SettingsStore
    let applyCloudflareEnabled: (Bool) -> Void

    func persistDefaultModel(_ model: ModelType) {
        settingsStore.defaultModel = model
    }

    func persistDefaultEffort(_ effort: ReasoningEffort) {
        settingsStore.defaultEffort = effort
    }

    func persistDefaultBackgroundModeEnabled(_ enabled: Bool) {
        settingsStore.defaultBackgroundModeEnabled = enabled
    }

    func persistDefaultServiceTier(_ serviceTier: ServiceTier) {
        settingsStore.defaultServiceTier = serviceTier
    }

    func persistAppTheme(_ theme: AppTheme) {
        settingsStore.appTheme = theme
    }

    func persistHapticEnabled(_ enabled: Bool) {
        settingsStore.hapticEnabled = enabled
    }

    func persistCloudflareEnabled(_ enabled: Bool) {
        settingsStore.cloudflareGatewayEnabled = enabled
        applyCloudflareEnabled(enabled)
    }
}

@MainActor
private func resolvedAppVersionString() -> String {
    let info = Bundle.main.infoDictionary
    let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
    let buildNumber = info?["CFBundleVersion"] as? String ?? "?"
    return "\(shortVersion) (\(buildNumber))"
}

@MainActor
private func resolvedPlatformString() -> String {
    let device = UIDevice.current
    let osName: String

    switch device.userInterfaceIdiom {
    case .pad:
        osName = "iPadOS"
    default:
        osName = "iOS"
    }

    let version = device.systemVersion
    let majorVersion = Int(version.components(separatedBy: ".").first ?? "0") ?? 0

    if majorVersion >= 26 {
        return "\(osName) \(version) · Liquid Glass"
    }

    return "\(osName) \(version)"
}

private struct SettingsErrorResponseDTO: Decodable {
    let message: String?
    let error: ResponsesErrorDTO?
}
