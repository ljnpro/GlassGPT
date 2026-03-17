extension SettingsScreenStore {
    func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        do {
            try apiKeyStore.saveAPIKey(trimmedKey)
            apiKey = trimmedKey
            saveConfirmation = true
            HapticService.shared.notify(.success)
        } catch {
            Loggers.settings.error("Failed to save API key: \(error.localizedDescription)")
        }
    }

    func clearAPIKey() {
        apiKey = ""
        apiKeyStore.deleteAPIKey()
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
}
