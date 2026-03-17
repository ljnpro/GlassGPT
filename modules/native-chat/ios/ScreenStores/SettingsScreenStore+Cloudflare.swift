import Foundation

extension SettingsScreenStore {
    func checkCloudflareHealth() async {
        guard cloudflareEnabled else {
            cloudflareHealthStatus = .unknown
            isCheckingCloudflareHealth = false
            return
        }

        let typedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey: String
        if !typedKey.isEmpty {
            trimmedKey = typedKey
        } else {
            trimmedKey = apiKeyStore.loadAPIKey()?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        }
        guard !trimmedKey.isEmpty else {
            cloudflareHealthStatus = .error("No API key configured")
            isCheckingCloudflareHealth = false
            return
        }

        let gatewayRequest: URLRequest
        do {
            gatewayRequest = try requestBuilder.modelsRequest(apiKey: trimmedKey)
        } catch {
            cloudflareHealthStatus = .error("Invalid gateway URL")
            isCheckingCloudflareHealth = false
            return
        }

        isCheckingCloudflareHealth = true
        cloudflareHealthStatus = .checking
        var request = gatewayRequest
        request.url = URL(string: "\(configurationProvider.cloudflareGatewayBaseURL)/models")

        do {
            let (data, response) = try await transport.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                cloudflareHealthStatus = .error("Invalid gateway response")
                isCheckingCloudflareHealth = false
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                cloudflareHealthStatus = .connected
            } else {
                let message = Self.parseErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)"
                cloudflareHealthStatus = .error(message)
            }
        } catch {
            cloudflareHealthStatus = .error(error.localizedDescription)
        }

        isCheckingCloudflareHealth = false
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        do {
            let payload = try JSONCoding.decode(SettingsErrorResponseDTO.self, from: data)
            if let message = payload.message, !message.isEmpty {
                return message
            }
            if let message = payload.error?.message, !message.isEmpty {
                return message
            }
        } catch {
            return String(data: data, encoding: .utf8)
        }

        return String(data: data, encoding: .utf8)
    }
}

private struct SettingsErrorResponseDTO: Decodable {
    let message: String?
    let error: ResponsesErrorDTO?
}
