import ChatPersistenceCore
import ChatUIComponents
import Foundation

@MainActor
extension ChatStreamingCoordinator {
    /// Attempts to retry the streaming request after a connection failure.
    ///
    /// - Parameters:
    ///   - session: The reply session to retry.
    ///   - streamID: The current stream identifier.
    ///   - reconnectAttempt: The current attempt number.
    ///   - dryRun: When `true`, only checks feasibility without executing the retry.
    /// - Returns: `true` if a retry is possible (or was executed).
    func retryStreamIfPossible(
        session: ReplySession,
        streamID: UUID,
        reconnectAttempt: Int,
        dryRun: Bool = false
    ) async -> Bool {
        let nextAttempt = reconnectAttempt + 1
        guard nextAttempt < Self.maxReconnectAttempts else {
            return false
        }

        if dryRun { return true }

        let delay = Self.reconnectBaseDelay * UInt64(1 << reconnectAttempt)
        #if DEBUG
        Loggers.chat.debug("[VM] Retrying full stream in \(Double(delay) / 1_000_000_000)s")
        #endif

        do {
            try await Task.sleep(nanoseconds: delay)
        } catch {
            return true
        }

        guard sessions.isSessionActive(session),
              let runtimeActor = await sessions.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID)
        else {
            return true
        }

        state.hapticService.impact(.light, isEnabled: state.hapticsEnabled)
        startStreamingRequest(for: session, reconnectAttempt: nextAttempt)
        return true
    }
}
