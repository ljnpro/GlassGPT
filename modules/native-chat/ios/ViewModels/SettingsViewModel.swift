import Foundation
import SwiftUI

enum CloudflareHealthStatus: Equatable {
    case unknown
    case checking
    case connected
    case error(String)
}

@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - State

    var apiKey: String = ""
    var isAPIKeyValid: Bool?
    var isValidating: Bool = false
    var saveConfirmation: Bool = false

    var cloudflareHealthStatus: CloudflareHealthStatus = .unknown
    var isCheckingCloudflareHealth: Bool = false

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

    var cloudflareEnabled: Bool {
        didSet {
            guard cloudflareEnabled != oldValue else { return }
            FeatureFlags.useCloudflareGateway = cloudflareEnabled
            if !cloudflareEnabled {
                cloudflareHealthStatus = .unknown
                isCheckingCloudflareHealth = false
            }
        }
    }

    // MARK: - Available efforts for current default model

    var availableDefaultEfforts: [ReasoningEffort] {
        defaultModel.availableEfforts
    }

    // MARK: - Dependencies

    private let keychainService = KeychainService()
    private let openAIService = OpenAIService()

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

        self.cloudflareEnabled = FeatureFlags.useCloudflareGateway
        self.apiKey = keychainService.loadAPIKey() ?? ""

        if self.cloudflareEnabled {
            Task {
                await checkCloudflareHealth()
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
        if cloudflareEnabled {
            cloudflareHealthStatus = .unknown
        }
        HapticService.shared.impact(.medium)
    }

    func validateAPIKey() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            isAPIKeyValid = false
            return
        }

        isValidating = true
        isAPIKeyValid = await openAIService.validateAPIKey(trimmedKey)
        isValidating = false
        HapticService.shared.notify(isAPIKeyValid == true ? .success : .error)
    }

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
            trimmedKey = keychainService.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard !trimmedKey.isEmpty else {
            cloudflareHealthStatus = .error("No API key configured")
            isCheckingCloudflareHealth = false
            return
        }

        guard let url = URL(string: "\(FeatureFlags.cloudflareGatewayBaseURL)/models") else {
            cloudflareHealthStatus = .error("Invalid gateway URL")
            isCheckingCloudflareHealth = false
            return
        }

        isCheckingCloudflareHealth = true
        cloudflareHealthStatus = .checking

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10
            FeatureFlags.applyCloudflareAuthorization(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)

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

    // MARK: - Helpers

    private static func parseErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            return String(data: data, encoding: .utf8)
        }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }

        return String(data: data, encoding: .utf8)
    }
}
