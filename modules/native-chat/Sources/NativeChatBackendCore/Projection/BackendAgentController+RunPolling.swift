import BackendClient
import ChatProjectionPersistence
import Foundation

private struct DeltaPayload: Decodable {
    let textDelta: String?
}

private struct StatusPayload: Decodable {
    let visibleSummary: String?
}

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

    func streamOrPollRun(conversationServerID: String, runID: String, selectionToken: UUID) async {
        defer {
            if activeRunID == runID {
                activeRunID = nil
            }
            runPollingTask = nil
            isThinking = false
            isRunning = false
        }

        // Try SSE streaming first, fall back to polling on failure
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
            // SSE failed — fall back to polling
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
        isRunning = true

        for try await event in stream {
            guard visibleSelectionToken == selectionToken, !Task.isCancelled else {
                break
            }

            switch event.event {
            case "delta":
                do {
                    if let deltaData = event.data.data(using: .utf8) {
                        let payload = try JSONDecoder().decode(DeltaPayload.self, from: deltaData)
                        if let textDelta = payload.textDelta {
                            currentStreamingText += textDelta
                        }
                    }
                } catch {
                    // Skip malformed delta events
                }

            case "status":
                do {
                    if let statusData = event.data.data(using: .utf8) {
                        let payload = try JSONDecoder().decode(StatusPayload.self, from: statusData)
                        if let summary = payload.visibleSummary {
                            try await loader.applyIncrementalSync()
                            try await refreshVisibleConversation()
                            let run = try await client.fetchRun(runID)
                            lastRunSummary = run
                            processSnapshot = BackendConversationSupport.processSnapshot(
                                for: run,
                                progressLabel: summary
                            )
                        }
                    }
                } catch {
                    // Skip malformed status events
                }

            case "done":
                try await setCurrentConversation(
                    loader.refreshConversationDetail(serverID: conversationServerID)
                )
                syncVisibleState()
                currentStreamingText = ""
                return

            case "error":
                errorMessage = event.data
                return

            default:
                try await loader.applyIncrementalSync()
                try await refreshVisibleConversation()
            }
        }

        // Stream ended; do final refresh
        do {
            guard visibleSelectionToken == selectionToken else { return }
            try await setCurrentConversation(
                loader.refreshConversationDetail(serverID: conversationServerID)
            )
            syncVisibleState()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
