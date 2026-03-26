import Foundation
import OpenAITransport

enum AgentRecoveryStreamMonitoring {
    private static let inactivityTimeout: Duration = .seconds(2)

    @MainActor
    static func monitoredStream(
        _ stream: AsyncStream<StreamEvent>,
        onTimeout: @escaping @MainActor () -> Void
    ) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            let proxyTask = Task { @MainActor in
                var timeoutTask = scheduleTimeout(onTimeout: onTimeout)
                defer { timeoutTask.cancel() }

                for await event in stream {
                    if Task.isCancelled {
                        break
                    }

                    timeoutTask.cancel()
                    continuation.yield(event)
                    timeoutTask = scheduleTimeout(onTimeout: onTimeout)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                proxyTask.cancel()
            }
        }
    }

    @MainActor
    private static func scheduleTimeout(
        onTimeout: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            do {
                try await Task.sleep(for: inactivityTimeout)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            onTimeout()
        }
    }
}
