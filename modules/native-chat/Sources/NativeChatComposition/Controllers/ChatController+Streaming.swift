import Foundation

@MainActor
extension ChatController {
    func startStreamingRequest(reconnectAttempt: Int = 0) {
        streamingCoordinator.startStreamingRequest(reconnectAttempt: reconnectAttempt)
    }

    func startStreamingRequest(for session: ReplySession, reconnectAttempt: Int = 0) {
        streamingCoordinator.startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }
}
