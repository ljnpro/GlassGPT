import Foundation

@MainActor
extension ChatScreenStore {
    func applyStreamEvent(_ event: StreamEvent, to session: ResponseSession, animated: Bool) -> StreamEventDisposition {
        conversationRuntime.streamEventCoordinator.apply(event, to: session, animated: animated)
    }
}
