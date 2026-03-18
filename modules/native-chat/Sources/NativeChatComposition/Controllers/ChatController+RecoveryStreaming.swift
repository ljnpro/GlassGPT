import Foundation

@MainActor
extension ChatController {
    func startStreamingRecovery(
        session: ReplySession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        await recoveryCoordinator.startStreamingRecovery(
            session: session,
            responseId: responseId,
            lastSeq: lastSeq,
            apiKey: apiKey,
            useDirectEndpoint: useDirectEndpoint
        )
    }
}
