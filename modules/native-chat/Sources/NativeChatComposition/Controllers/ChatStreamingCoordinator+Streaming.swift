import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatRuntimeWorkflows
import ChatUIComponents
import Foundation
import OpenAITransport
import os

private let streamingSignposter = OSSignposter(subsystem: "GlassGPT", category: "streaming")

final class StreamingProgress {
    var receivedConnectionLost = false
    var didReceiveCompletedEvent = false
    var pendingRecoveryResponseId: String?
    var pendingRecoveryError: String?
}

@MainActor
extension ChatStreamingCoordinator {
    func startStreamingRequest(for session: ReplySession, reconnectAttempt: Int = 0) {
        let signpostID = streamingSignposter.makeSignpostID()
        let signpostState = streamingSignposter.beginInterval("StreamingRequest", id: signpostID)
        defer { streamingSignposter.endInterval("StreamingRequest", signpostState) }

        guard let requestMessages = session.request.messages else { return }
        guard let execution = services.sessionRegistry.execution(for: session.messageID) else { return }

        execution.task?.cancel()
        execution.task = Task { @MainActor [weak self] in
            guard let self else { return }
            let streamID = UUID()
            _ = await sessions.applyRuntimeTransition(
                .beginStreaming(
                    streamID: streamID,
                    route: sessions.runtimeRoute(for: session)
                ),
                to: session
            )
            sessions.syncVisibleState(from: session)

            let stream = execution.service.streamChat(
                apiKey: session.request.apiKey,
                messages: requestMessages,
                model: session.request.model,
                reasoningEffort: session.request.effort,
                backgroundModeEnabled: session.request.usesBackgroundMode,
                serviceTier: session.request.serviceTier
            )

            let progress = StreamingProgress()
            defer { services.endBackgroundTask() }

            for await event in stream {
                guard !Task.isCancelled else { return }
                guard await handleStreamingEvent(
                    event,
                    session: session,
                    streamID: streamID,
                    progress: progress
                ) else {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            await finishStreamingRequest(
                session: session,
                streamID: streamID,
                reconnectAttempt: reconnectAttempt,
                progress: progress
            )
        }
    }

}
