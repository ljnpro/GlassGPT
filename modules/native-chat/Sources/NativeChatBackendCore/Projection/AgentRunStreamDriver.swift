import BackendClient
import Foundation

@MainActor
package extension BackendAgentController {
    func loadCachedConversationIfAvailable(serverID: String) {
        do {
            guard let cachedConversation = try loader.loadCachedConversation(serverID: serverID) else {
                return
            }
            _ = applyLoadedConversation(cachedConversation)
            syncVisibleState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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

    private static let maxStreamRetries = 3

    func streamOrPollRun(conversationServerID: String, runID: String, selectionToken: UUID) async {
        defer {
            if activeRunID == runID {
                activeRunID = nil
            }
            runPollingTask = nil
            isThinking = false
            isRunning = false
        }

        for attempt in 0 ..< Self.maxStreamRetries {
            do {
                try await streamRun(
                    conversationServerID: conversationServerID,
                    runID: runID,
                    selectionToken: selectionToken
                )
                return
            } catch is CancellationError {
                return
            } catch {
                if attempt < Self.maxStreamRetries - 1 {
                    let backoff = pow(2.0, Double(attempt)) + Double.random(in: 0 ... 0.5)
                    do {
                        try await Task.sleep(for: .seconds(backoff))
                    } catch {
                        return
                    }
                    continue
                }
                // All stream retries exhausted — fall back to polling.
            }
        }

        await pollRun(
            conversationServerID: conversationServerID,
            runID: runID,
            selectionToken: selectionToken
        )
    }

    private func streamRun(
        conversationServerID: String,
        runID: String,
        selectionToken: UUID
    ) async throws {
        let stream = client.streamRun(runID)
        beginAgentStream()

        let batcher = StreamEventBatcher<SSEEvent> { [weak self] batch in
            try await self?.flushAgentStreamBatch(
                batch,
                conversationServerID: conversationServerID,
                runID: runID
            )
        }

        for try await event in stream {
            guard visibleSelectionToken == selectionToken, !Task.isCancelled else {
                batcher.cancel()
                break
            }

            if event.event == "done" || event.event == "error" {
                try await batcher.flushNow()
                let outcome = try await handleAgentStreamEvent(
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
        await finishAgentStreamAfterTermination(
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
                lastRunSummary = run
                processSnapshot = BackendConversationSupport.processSnapshot(
                    for: run,
                    progressLabel: run.visibleSummary
                )
                isRunning = run.status == .queued || run.status == .running
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
            try await setCurrentConversation(
                loader.refreshConversationDetail(serverID: conversationServerID)
            )
            syncVisibleState()
            clearAgentLiveSurface()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
