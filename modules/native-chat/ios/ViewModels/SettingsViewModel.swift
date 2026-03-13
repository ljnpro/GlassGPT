import Foundation
import SwiftUI

enum RelayHealthStatus: Equatable {
    case unknown
    case checking
    case healthy(uptime: Int, activeRuns: Int)
    case error(String)
}

private struct RelayHealthResponse: Decodable {
    let status: String
    let uptime: Int
    let activeRuns: Int
    let version: String
}

@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - State

    var apiKey: String = ""
    var isAPIKeyValid: Bool?
    var isValidating: Bool = false
    var saveConfirmation: Bool = false

    var relayHealthStatus: RelayHealthStatus = .unknown
    var relayVersion: String?
    var isRelayAutoDetected: Bool = FeatureFlags.isRelayAutoDetected

    // MARK: - Persisted Settings (stored properties for @Observable tracking)

    var defaultModel: ModelType {
        didSet {
            UserDefaults.standard.set(defaultModel.rawValue, forKey: "defaultModel")
            if !defaultModel.availableEfforts.contains(defaultEffort) {
                defaultEffort = defaultModel.defaultEffort
            }
        }
    }

    var defaultEffort: ReasoningEffort {
        didSet {
            UserDefaults.standard.set(defaultEffort.rawValue, forKey: "defaultEffort")
        }
    }

    var appTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(appTheme.rawValue, forKey: "appTheme")
        }
    }

    var hapticEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticEnabled, forKey: "hapticEnabled")
        }
    }

    var relayServerEnabled: Bool {
        didSet {
            FeatureFlags.useRelayServer = relayServerEnabled
        }
    }

    var relayServerURL: String {
        didSet {
            let trimmed = relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines)

            if relayServerURL != trimmed {
                relayServerURL = trimmed
                return
            }

            FeatureFlags.relayServerURL = trimmed

            let resolvedURL = FeatureFlags.relayServerURL
            if relayServerURL != resolvedURL {
                relayServerURL = resolvedURL
                return
            }

            isRelayAutoDetected = FeatureFlags.isRelayAutoDetected
            relayServerEnabled = FeatureFlags.useRelayServer

            if resolvedURL.isEmpty {
                relayHealthStatus = .unknown
                relayVersion = nil
            }
        }
    }

    // MARK: - Available efforts for current default model

    var availableDefaultEfforts: [ReasoningEffort] {
        defaultModel.availableEfforts
    }

    var isCheckingRelayHealth: Bool {
        if case .checking = relayHealthStatus {
            return true
        }
        return false
    }

    // MARK: - Dependencies

    private let keychainService = KeychainService()

    // MARK: - Init

    init() {
        if let raw = UserDefaults.standard.string(forKey: "defaultModel"),
           let model = ModelType(rawValue: raw) {
            self.defaultModel = model
        } else {
            self.defaultModel = .gpt5_4
        }

        if let raw = UserDefaults.standard.string(forKey: "defaultEffort"),
           let effort = ReasoningEffort(rawValue: raw) {
            self.defaultEffort = effort
        } else {
            self.defaultEffort = .medium
        }

        if let raw = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: raw) {
            self.appTheme = theme
        } else {
            self.appTheme = .system
        }

        if let val = UserDefaults.standard.object(forKey: "hapticEnabled") as? Bool {
            self.hapticEnabled = val
        } else {
            self.hapticEnabled = true
        }

        self.relayServerEnabled = FeatureFlags.useRelayServer
        self.relayServerURL = FeatureFlags.relayServerURL
        self.apiKey = keychainService.loadAPIKey() ?? ""
        self.isRelayAutoDetected = FeatureFlags.isRelayAutoDetected

        if !self.relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                await checkRelayHealth()
            }
        }
    }

    // MARK: - Actions

    func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        try? keychainService.saveAPIKey(trimmedKey)
        apiKey = trimmedKey
        saveConfirmation = true
        HapticService.shared.notify(.success)
    }

    func clearAPIKey() {
        apiKey = ""
        keychainService.deleteAPIKey()
        isAPIKeyValid = nil
        HapticService.shared.impact(.medium)
    }

    func validateAPIKey() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            isAPIKeyValid = false
            return
        }

        isValidating = true

        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            isAPIKeyValid = false
            isValidating = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            isAPIKeyValid = httpResponse?.statusCode == 200
        } catch {
            isAPIKeyValid = false
        }

        isValidating = false
        HapticService.shared.notify(isAPIKeyValid == true ? .success : .error)
    }

    func checkRelayHealth() async {
        let resolvedURL = FeatureFlags.relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        relayServerURL = resolvedURL
        isRelayAutoDetected = FeatureFlags.isRelayAutoDetected

        guard !resolvedURL.isEmpty else {
            relayHealthStatus = .error("Relay server URL is not configured.")
            relayVersion = nil
            return
        }

        guard let baseURL = URL(string: resolvedURL) else {
            relayHealthStatus = .error("Relay server URL is invalid.")
            relayVersion = nil
            return
        }

        let relayBasePath = RELAY_HTTP_BASE_PATH.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let healthURL = baseURL
            .appendingPathComponent(relayBasePath)
            .appendingPathComponent("health")

        relayHealthStatus = .checking

        do {
            var request = URLRequest(url: healthURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                relayHealthStatus = .error("Invalid response from relay server.")
                relayVersion = nil
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = Self.parseErrorMessage(from: data) ?? "Relay health check failed with status \(httpResponse.statusCode)."
                relayHealthStatus = .error(message)
                relayVersion = nil
                return
            }

            let decoded = try JSONDecoder().decode(RelayHealthResponse.self, from: data)
            relayVersion = decoded.version

            let normalizedStatus = decoded.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalizedStatus == "ok" || normalizedStatus == "healthy" || normalizedStatus == "up" else {
                relayHealthStatus = .error("Relay reported status: \(decoded.status)")
                return
            }

            relayHealthStatus = .healthy(
                uptime: max(0, decoded.uptime),
                activeRuns: max(0, decoded.activeRuns)
            )
        } catch is DecodingError {
            relayHealthStatus = .error("Relay health response could not be decoded.")
            relayVersion = nil
        } catch {
            relayHealthStatus = .error(error.localizedDescription)
            relayVersion = nil
        }
    }

    // MARK: - Helpers

    private static func parseErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSONDictionary
        else {
            return String(data: data, encoding: .utf8)
        }

        if let message = json.string("message"), !message.isEmpty {
            return message
        }

        if let error = json.dictionary("error"), let message = error.string("message"), !message.isEmpty {
            return message
        }

        return String(data: data, encoding: .utf8)
    }
}
