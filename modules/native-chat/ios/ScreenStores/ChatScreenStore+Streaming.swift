import Foundation

@MainActor
extension ChatScreenStore {

    // MARK: - Send Message

    @discardableResult
    func sendMessage(text rawText: String) -> Bool {
        conversationRuntime.streamingCoordinator.sendMessage(text: rawText)
    }

    // MARK: - Core Streaming Logic

    static let maxReconnectAttempts = StreamingEffectHandler.maxReconnectAttempts
    static let reconnectBaseDelay: UInt64 = StreamingEffectHandler.reconnectBaseDelay

    func startStreamingRequest(reconnectAttempt: Int = 0) {
        conversationRuntime.streamingCoordinator.startStreamingRequest(reconnectAttempt: reconnectAttempt)
    }

    func startStreamingRequest(for session: ResponseSession, reconnectAttempt: Int = 0) {
        conversationRuntime.streamingCoordinator.startStreamingRequest(for: session, reconnectAttempt: reconnectAttempt)
    }

    // MARK: - Tool Call & Citation Persistence

    func persistToolCallsAndCitations() {
        conversationRuntime.streamingCoordinator.persistToolCallsAndCitations()
    }

    // MARK: - Draft Persistence

    func saveDraftIfNeeded() {
        conversationRuntime.streamingCoordinator.saveDraftIfNeeded()
    }

    func saveDraftNow() {
        conversationRuntime.streamingCoordinator.saveDraftNow()
    }

    func finalizeDraft() {
        conversationRuntime.streamingCoordinator.finalizeDraft()
    }

    func finalizeDraftAsPartial() {
        conversationRuntime.streamingCoordinator.finalizeDraftAsPartial()
    }

    func removeEmptyDraft() {
        conversationRuntime.streamingCoordinator.removeEmptyDraft()
    }

    // MARK: - Stop Generation

    func stopGeneration(savePartial: Bool = true) {
        conversationRuntime.streamingCoordinator.stopGeneration(savePartial: savePartial)
    }
}
