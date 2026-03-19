import ChatApplication
import ChatPersistenceCore
import Foundation
import OpenAITransport

@MainActor
struct SettingsCloudflareHealthResolver {
    let apiKeyStore: PersistedAPIKeyStore
    let loadConfigurationProvider: () -> OpenAIConfigurationProvider

    func resolve(typedAPIKey: String, gatewayEnabled: Bool) -> CloudflareHealthStatus {
        guard gatewayEnabled else {
            return .unknown
        }

        let configurationProvider = loadConfigurationProvider()
        let gatewayBaseURL = configurationProvider.cloudflareGatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gatewayBaseURL.isEmpty else {
            return .gatewayUnavailable
        }

        let gatewayToken = configurationProvider.cloudflareAIGToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gatewayToken.isEmpty else {
            return .gatewayUnavailable
        }

        guard isValidGatewayModelsURL(gatewayBaseURL) else {
            return .invalidGatewayURL
        }

        guard !resolvedAPIKey(typedAPIKey: typedAPIKey).isEmpty else {
            return .missingAPIKey
        }

        return .unknown
    }

    func resolvedAPIKey(typedAPIKey: String) -> String {
        let typedKey = typedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedKey = apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return typedKey.isEmpty ? storedKey : typedKey
    }

    private func isValidGatewayModelsURL(_ baseURL: String) -> Bool {
        guard let url = URL(string: "\(baseURL)/models"),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            return false
        }
        return true
    }
}

@MainActor
struct SettingsCredentialHandlerImpl: SettingsCredentialHandler {
    let apiKeyStore: PersistedAPIKeyStore
    let openAIService: OpenAIService
    let requestBuilder: OpenAIRequestBuilder
    let transport: OpenAIDataTransport
    let healthResolver: SettingsCloudflareHealthResolver

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
        healthResolver.resolve(typedAPIKey: typedAPIKey, gatewayEnabled: gatewayEnabled)
    }

    func checkCloudflareHealth(typedAPIKey: String, gatewayEnabled: Bool) async -> CloudflareHealthStatus {
        let localStatus = healthResolver.resolve(typedAPIKey: typedAPIKey, gatewayEnabled: gatewayEnabled)
        guard localStatus == .unknown else {
            return localStatus
        }

        let trimmedKey = healthResolver.resolvedAPIKey(typedAPIKey: typedAPIKey)
        let gatewayRequest: URLRequest
        do {
            gatewayRequest = try requestBuilder.modelsRequest(apiKey: trimmedKey)
        } catch {
            return .invalidGatewayURL
        }

        let configurationProvider = healthResolver.loadConfigurationProvider()
        var request = gatewayRequest
        let gatewayBaseURL = configurationProvider.cloudflareGatewayBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        request.url = URL(string: "\(gatewayBaseURL)/models")

        do {
            let (data, response) = try await transport.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .remoteError("Invalid gateway response")
            }

            if (200 ... 299).contains(httpResponse.statusCode) {
                return .connected
            }

            do {
                let payload = try JSONCoding.decode(SettingsErrorResponseDTO.self, from: data)
                if let message = payload.message ?? payload.error?.message, !message.isEmpty {
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

private struct SettingsErrorResponseDTO: Decodable {
    let message: String?
    let error: ResponsesErrorDTO?
}
