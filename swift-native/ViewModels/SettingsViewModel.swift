import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - State

    var apiKey: String = ""
    var isAPIKeyValid: Bool?
    var isValidating: Bool = false
    var saveConfirmation: Bool = false

    // MARK: - Persisted Settings (via AppStorage)

    @ObservationIgnored
    @AppStorage("defaultModel") var defaultModelRaw: String = ModelType.gpt5_4.rawValue

    @ObservationIgnored
    @AppStorage("defaultEffort") var defaultEffortRaw: String = ReasoningEffort.high.rawValue

    @ObservationIgnored
    @AppStorage("appTheme") var appThemeRaw: String = AppTheme.system.rawValue

    @ObservationIgnored
    @AppStorage("hapticEnabled") var hapticEnabled: Bool = true

    // MARK: - Computed Bindings

    var defaultModel: ModelType {
        get { ModelType(rawValue: defaultModelRaw) ?? .gpt5_4 }
        set { defaultModelRaw = newValue.rawValue }
    }

    var defaultEffort: ReasoningEffort {
        get { ReasoningEffort(rawValue: defaultEffortRaw) ?? .high }
        set { defaultEffortRaw = newValue.rawValue }
    }

    var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .system }
        set { appThemeRaw = newValue.rawValue }
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

        do {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
