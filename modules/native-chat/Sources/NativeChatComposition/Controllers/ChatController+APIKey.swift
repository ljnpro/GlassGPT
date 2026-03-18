import Foundation

@MainActor
extension ChatController {
    var apiKey: String {
        sendCoordinator.apiKey
    }

    var hasAPIKey: Bool {
        sendCoordinator.hasAPIKey
    }
}
