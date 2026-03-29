import Foundation

/// Retries live streaming a run a bounded number of times before falling back to polling.
@MainActor
package func runStreamWithRetryAndPolling(
    maxStreamRetries: Int = 3,
    stream: () async throws -> Void,
    poll: () async -> Void
) async {
    for attempt in 0 ..< maxStreamRetries {
        do {
            try await stream()
            return
        } catch is CancellationError {
            return
        } catch {
            if attempt < maxStreamRetries - 1 {
                let backoff = pow(2.0, Double(attempt)) + Double.random(in: 0 ... 0.5)
                do {
                    try await Task.sleep(for: .seconds(backoff))
                } catch {
                    return
                }
                continue
            }
        }
    }

    await poll()
}
