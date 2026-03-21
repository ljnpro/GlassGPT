import ChatPersistenceCore
import ChatRuntimeWorkflows
import Foundation
import OpenAITransport

@MainActor
extension ChatRecoveryCoordinator {
    func startStreamingRecovery(
        session: ReplySession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        let streamID = UUID()
        _ = await sessions.applyRuntimeTransition(.beginRecoveryStream(streamID: streamID), to: session)
        sessions.syncVisibleState(from: session)
        guard let execution = services.sessionRegistry.execution(for: session.messageID) else { return }

        let stream = execution.service.streamRecovery(
            responseId: responseId,
            startingAfter: lastSeq,
            apiKey: apiKey,
            useDirectBaseURL: useDirectEndpoint
        )

        let progress = RecoveryStreamProgress()
        let gatewayFallbackTask = makeRecoveryGatewayFallbackTask(
            session: session,
            streamID: streamID,
            execution: execution,
            useDirectEndpoint: useDirectEndpoint,
            progress: progress
        )
        defer { gatewayFallbackTask?.cancel() }

        for await event in stream {
            guard await handleRecoveryStreamEvent(
                event,
                session: session,
                streamID: streamID,
                execution: execution,
                progress: progress,
                gatewayFallbackTask: gatewayFallbackTask
            ) else {
                return
            }
        }

        await finishRecoveryStreaming(
            session: session,
            streamID: streamID,
            responseId: responseId,
            lastSeq: lastSeq,
            apiKey: apiKey,
            useDirectEndpoint: useDirectEndpoint,
            execution: execution,
            progress: progress
        )
    }
}
