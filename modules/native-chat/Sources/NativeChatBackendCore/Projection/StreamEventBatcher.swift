import Foundation

/// Accumulates stream events over a short window and flushes them as a single batch,
/// reducing `@Observable` mutation frequency from 100+/sec to ~15/sec.
@MainActor
package final class StreamEventBatcher<Event: Sendable> {
    private var buffer: [Event] = []
    private var flushTask: Task<Void, Never>?
    private let flushInterval: Duration
    private let onFlush: @MainActor ([Event]) async throws -> Void
    private let onFlushError: @MainActor (Error) -> Void

    /// Creates a batcher with the given flush interval and callback.
    package init(
        flushInterval: Duration = .milliseconds(16),
        onFlushError: @escaping @MainActor (Error) -> Void = { error in
            assertionFailure("StreamEventBatcher onFlush threw: \(error)")
        },
        onFlush: @escaping @MainActor ([Event]) async throws -> Void
    ) {
        self.flushInterval = flushInterval
        self.onFlushError = onFlushError
        self.onFlush = onFlush
    }

    /// Enqueues an event into the buffer and schedules a flush if needed.
    package func enqueue(_ event: Event) {
        buffer.append(event)
        scheduleFlushIfNeeded()
    }

    /// Immediately flushes all buffered events, bypassing the timer.
    package func flushNow() async throws {
        flushTask?.cancel()
        flushTask = nil
        let batch = buffer
        buffer = []
        guard !batch.isEmpty else { return }
        try await onFlush(batch)
    }

    /// Cancels the pending flush and discards all buffered events.
    package func cancel() {
        flushTask?.cancel()
        flushTask = nil
        buffer = []
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: self?.flushInterval ?? .milliseconds(66))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            flushTask = nil
            let batch = buffer
            buffer = []
            guard !batch.isEmpty else { return }
            do {
                try await onFlush(batch)
            } catch is CancellationError {
                return
            } catch {
                onFlushError(error)
            }
        }
    }
}
