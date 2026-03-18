import ChatPersistenceCore
import ChatUIComponents
import Foundation

@MainActor
extension ChatStreamingCoordinator {
    func retryStreamIfPossible(
        session: ReplySession,
        streamID: UUID,
        reconnectAttempt: Int
    ) async -> Bool {
        let nextAttempt = reconnectAttempt + 1
        guard nextAttempt < Self.maxReconnectAttempts else {
            return false
        }

        let delay = Self.reconnectBaseDelay * UInt64(1 << reconnectAttempt)
        #if DEBUG
        Loggers.chat.debug("[VM] Retrying full stream in \(Double(delay) / 1_000_000_000)s")
        #endif

        do {
            try await Task.sleep(nanoseconds: delay)
        } catch {
            return true
        }

        guard controller.isSessionActive(session),
              let runtimeActor = await controller.runtimeSession(for: session),
              await runtimeActor.isActiveStream(streamID) else {
            return true
        }

        HapticService.shared.impact(.light)
        startStreamingRequest(for: session, reconnectAttempt: nextAttempt)
        return true
    }
}
