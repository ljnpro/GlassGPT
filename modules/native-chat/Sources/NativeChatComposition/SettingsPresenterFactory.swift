import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import GeneratedFilesInfra
import OpenAITransport
import Foundation
import UIKit

@MainActor
func makeSettingsPresenter(
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
        checkCloudflareHealth: { typedAPIKey, gatewayEnabled in
            guard gatewayEnabled else {
                return .unknown
            }

            let trimmedKey: String
            let typedKey = typedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !typedKey.isEmpty {
                trimmedKey = typedKey
            } else {
                trimmedKey = apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }

            guard !trimmedKey.isEmpty else {
                return .error("No API key configured")
            }

            let gatewayRequest: URLRequest
            do {
                gatewayRequest = try requestBuilder.modelsRequest(apiKey: trimmedKey)
            } catch {
                return .error("Invalid gateway URL")
            }

            var request = gatewayRequest
            request.url = URL(string: "\(mutableConfigurationProvider.cloudflareGatewayBaseURL)/models")

            do {
                let (data, response) = try await transport.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    return .error("Invalid gateway response")
                }

                if (200...299).contains(httpResponse.statusCode) {
                    return .connected
                }

                do {
                    let payload = try JSONCoding.decode(SettingsErrorResponseDTO.self, from: data)
                    if let message = payload.message ?? payload.error?.message,
                       !message.isEmpty {
                        return .error(message)
                    }
                } catch {
                }

                return .error(String(data: data, encoding: .utf8) ?? "Status \(httpResponse.statusCode)")
            } catch {
                return .error(error.localizedDescription)
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
