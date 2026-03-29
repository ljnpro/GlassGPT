import BackendClient
import BackendContracts
import Foundation

/// Outcome returned by a streamed run event handler.
package enum BackendConversationStreamOutcome {
    case continueLoop
    case finish
}

/// Shared live-stream and polling behavior for backend conversation controllers.
@MainActor
package protocol BackendConversationRunStreamDriving: BackendConversationProjectionController {
    func beginLiveStream()
    func flushLiveStreamBatch(
        _ batch: [SSEEvent],
        conversationServerID: String,
        runID: String
    ) async throws
    func handleLiveTerminalEvent(
        _ event: SSEEvent,
        conversationServerID: String,
        runID: String
    ) async throws -> BackendConversationStreamOutcome
    func applyPolledRunSummary(_ run: RunSummaryDTO)
    func clearLiveSurface()
}

@MainActor
package extension BackendConversationRunStreamDriving {
    /// Applies shared active/terminal state changes from a polled run summary.
    func applySharedPolledRunSummary(_ run: RunSummaryDTO) {
        isRunActive = run.status == .queued || run.status == .running
    }

    /// Default polling summary hook for controllers without additional mode-specific state.
    func applyPolledRunSummary(_ run: RunSummaryDTO) {
        applySharedPolledRunSummary(run)
    }

    /// Starts the long-lived task that streams or polls a specific backend run.
    func startRunPolling(conversationServerID: String, runID: String, selectionToken: UUID) {
        runPollingTask?.cancel()
        runPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await streamOrPollRun(
                conversationServerID: conversationServerID,
                runID: runID,
                selectionToken: selectionToken
            )
        }
    }

    /// Attempts a live SSE stream first, then falls back to polling if needed.
    func streamOrPollRun(conversationServerID: String, runID: String, selectionToken: UUID) async {
        defer {
            if activeRunID == runID {
                activeRunID = nil
            }
            lastStreamEventID = nil
            runPollingTask = nil
            isThinking = false
            isRunActive = false
        }
        await runStreamWithRetryAndPolling(
            stream: {
                try await streamRun(
                    conversationServerID: conversationServerID,
                    runID: runID,
                    selectionToken: selectionToken
                )
            },
            poll: {
                await pollRun(
                    conversationServerID: conversationServerID,
                    runID: runID,
                    selectionToken: selectionToken
                )
            }
        )
    }

    private func streamRun(
        conversationServerID: String,
        runID: String,
        selectionToken: UUID
    ) async throws {
        do {
            let stream = try await client.streamRun(runID, lastEventID: lastStreamEventID)
            beginLiveStream()
            try await consumeStream(
                stream,
                conversationServerID: conversationServerID,
                runID: runID,
                selectionToken: selectionToken
            )
        } catch let error as BackendSSEStreamError {
            guard error == .unacceptableStatusCode(401) else {
                throw error
            }
            _ = try await client.refreshSession()
            let refreshedStream = try await client.streamRun(runID, lastEventID: lastStreamEventID)
            beginLiveStream()
            try await consumeStream(
                refreshedStream,
                conversationServerID: conversationServerID,
                runID: runID,
                selectionToken: selectionToken
            )
        }
    }

    private func consumeStream(
        _ stream: BackendSSEStream,
        conversationServerID: String,
        runID: String,
        selectionToken: UUID
    ) async throws {
        let batcher = StreamEventBatcher<SSEEvent>(
            onFlushError: { [weak self] error in
                self?.errorMessage = error.localizedDescription
            },
            onFlush: { [weak self] batch in
                try await self?.flushLiveStreamBatch(
                    batch,
                    conversationServerID: conversationServerID,
                    runID: runID
                )
            }
        )

        for try await event in stream {
            if let eventID = event.id, !eventID.isEmpty {
                lastStreamEventID = eventID
            }
            guard visibleSelectionToken == selectionToken, !Task.isCancelled else {
                batcher.cancel()
                break
            }

            if event.event == "done" || event.event == "error" {
                try await batcher.flushNow()
                let outcome = try await handleLiveTerminalEvent(
                    event,
                    conversationServerID: conversationServerID,
                    runID: runID
                )
                if outcome == .finish {
                    batcher.cancel()
                    return
                }
            } else {
                batcher.enqueue(event)
            }
        }

        batcher.cancel()
        await finishRunStreamAfterTermination(
            conversationServerID: conversationServerID,
            selectionToken: selectionToken
        )
    }

    private func pollRun(
        conversationServerID: String,
        runID: String,
        selectionToken: UUID
    ) async {
        var backoffSeconds: TimeInterval = 1
        let maxBackoff: TimeInterval = 15

        while !Task.isCancelled {
            do {
                try await loader.applyIncrementalSync()
                guard visibleSelectionToken == selectionToken else {
                    break
                }
                try await refreshVisibleConversation()
                let run = try await client.fetchRun(runID)
                applyPolledRunSummary(run)
                if run.status == .completed || run.status == .failed || run.status == .cancelled {
                    break
                }
                backoffSeconds = 1
            } catch is CancellationError {
                break
            } catch {
                errorMessage = error.localizedDescription
                backoffSeconds = min(backoffSeconds * 2, maxBackoff)
            }
            do {
                try await Task.sleep(for: .seconds(backoffSeconds))
            } catch {
                break
            }
        }

        do {
            guard visibleSelectionToken == selectionToken else {
                return
            }
            try await finalizeVisibleRun(conversationServerID: conversationServerID)
            clearLiveSurface()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishRunStreamAfterTermination(
        conversationServerID: String,
        selectionToken: UUID
    ) async {
        do {
            guard visibleSelectionToken == selectionToken else { return }
            try await finalizeVisibleRun(conversationServerID: conversationServerID)
            clearLiveSurface()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
