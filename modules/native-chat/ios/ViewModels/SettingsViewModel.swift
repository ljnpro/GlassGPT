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

    // MARK: - Persisted Settings

    /// We use UserDefaults directly (not @AppStorage) because @AppStorage
    /// combined with @ObservationIgnored prevents SwiftUI Picker from updating.
    var defaultModel: ModelType {
        get {
            if let raw = UserDefaults.standard.string(forKey: "defaultModel"),
               let model = ModelType(rawValue: raw) {
                return model
            }
            return .gpt5_4
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "defaultModel")
            // Validate effort for new model
            if !newValue.availableEfforts.contains(defaultEffort) {
                defaultEffort = newValue.defaultEffort
            }
        }
    }

    var defaultEffort: ReasoningEffort {
        get {
            if let raw = UserDefaults.standard.string(forKey: "defaultEffort"),
               let effort = ReasoningEffort(rawValue: raw) {
                return effort
            }
            return .medium  // Default is medium per user requirement
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "defaultEffort")
        }
    }

    var appTheme: AppTheme {
        get {
            if let raw = UserDefaults.standard.string(forKey: "appTheme"),
               let theme = AppTheme(rawValue: raw) {
                return theme
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appTheme")
        }
    }

    var hapticEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "hapticEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hapticEnabled") }
    }

    // MARK: - Available efforts for current default model

    var availableDefaultEfforts: [ReasoningEffort] {
        defaultModel.availableEfforts
    }

    // MARK: - Dependencies

    private let keychainService = KeychainService()

    // MARK: - Init

    init() {
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
