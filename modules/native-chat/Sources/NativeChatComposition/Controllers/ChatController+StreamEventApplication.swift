import Foundation
import OpenAITransport

@MainActor
extension ChatController {
    func applyStreamEvent(_ event: StreamEvent, to session: ReplySession, animated: Bool) async -> StreamEventDisposition {
        await streamingCoordinator.applyStreamEvent(event, to: session, animated: animated)
    }
}
