import Foundation

@MainActor
extension ChatScreenStore {
    var apiKey: String {
        apiKeyStore.loadAPIKey() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }
}
