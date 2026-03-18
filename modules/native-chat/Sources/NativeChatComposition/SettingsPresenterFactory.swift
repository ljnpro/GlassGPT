import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import GeneratedFilesInfra
import OpenAITransport
import Foundation
import UIKit

@MainActor
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

    let controller = SettingsSceneController(
        loadAPIKey: {
            apiKeyStore.loadAPIKey()
        },
        saveAPIKey: { trimmedKey in
            try apiKeyStore.saveAPIKey(trimmedKey)
        },
        clearAPIKey: {
            apiKeyStore.deleteAPIKey()
        },
        validateAPIKey: { trimmedKey in
            await openAIService.validateAPIKey(trimmedKey)
        },
        resolveCloudflareHealth: { typedAPIKey, gatewayEnabled in
            resolvedCloudflareHealth(typedAPIKey, gatewayEnabled)
        },
        checkCloudflareHealth: { typedAPIKey, gatewayEnabled in
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

            var request = gatewayRequest
            request.url = URL(string: "\(mutableConfigurationProvider.cloudflareGatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines))/models")

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
                }

                return .remoteError(String(data: data, encoding: .utf8) ?? "Status \(httpResponse.statusCode)")
            } catch {
                return .remoteError(error.localizedDescription)
            }
        },
        refreshGeneratedImageCacheSize: {
            await fileDownloadService.generatedImageCacheSize()
        },
        refreshGeneratedDocumentCacheSize: {
            await fileDownloadService.generatedDocumentCacheSize()
        },
        clearGeneratedImageCache: {
            await fileDownloadService.clearGeneratedImageCache()
            return await fileDownloadService.generatedImageCacheSize()
        },
        clearGeneratedDocumentCache: {
            await fileDownloadService.clearGeneratedDocumentCache()
            return await fileDownloadService.generatedDocumentCacheSize()
        },
        persistDefaultModel: { model in
            settingsStore.defaultModel = model
        },
        persistDefaultEffort: { effort in
            settingsStore.defaultEffort = effort
        },
        persistDefaultBackgroundModeEnabled: { enabled in
            settingsStore.defaultBackgroundModeEnabled = enabled
        },
        persistDefaultServiceTier: { serviceTier in
            settingsStore.defaultServiceTier = serviceTier
        },
        persistAppTheme: { theme in
            settingsStore.appTheme = theme
        },
        persistHapticEnabled: { enabled in
            settingsStore.hapticEnabled = enabled
        },
        persistCloudflareEnabled: { enabled in
            settingsStore.cloudflareGatewayEnabled = enabled
            mutableConfigurationProvider.useCloudflareGateway = enabled
        }
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
