import Foundation

@MainActor
final class ChatStreamingCoordinator {
    static let maxReconnectAttempts = 3
    static let reconnectBaseDelay: UInt64 = 1_000_000_000

    unowned let controller: ChatController

    init(controller: ChatController) {
        self.controller = controller
    }

    func startStreamingRequest(reconnectAttempt: Int = 0) {
        guard let session = controller.currentVisibleSession else { return }
        startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }
}
