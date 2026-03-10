import Foundation
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - State

    var apiKey: String = ""
    var isAPIKeyValid: Bool?
    var isValidating: Bool = false
    var saveConfirmation: Bool = false

    // MARK: - Persisted Settings (stored properties for @Observable tracking)

    var defaultModel: ModelType {
        didSet {
            UserDefaults.standard.set(defaultModel.rawValue, forKey: "defaultModel")
            // Validate effort for new model
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

    // MARK: - Available efforts for current default model

    var availableDefaultEfforts: [ReasoningEffort] {
        defaultModel.availableEfforts
    }

    // MARK: - Dependencies

    private let keychainService = KeychainService()

    // MARK: - Init

    init() {
        // Load persisted values from UserDefaults
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

        apiKey = keychainService.loadAPIKey() ?? ""
    }

    // MARK: - Actions

    func saveAPIKey() {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? keychainService.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
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
        guard !apiKey.isEmpty else {
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
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
}
