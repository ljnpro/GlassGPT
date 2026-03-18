import Foundation

@MainActor
extension ChatController {
    var apiKey: String {
        apiKeyStore.loadAPIKey() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }
}
