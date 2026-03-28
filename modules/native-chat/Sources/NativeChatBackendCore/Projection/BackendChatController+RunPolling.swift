import ChatProjectionPersistence
import Foundation

@MainActor
package extension BackendChatController {
    func loadCachedConversationIfAvailable(serverID: String) {
        do {
            guard let cachedConversation = try loader.loadCachedConversation(serverID: serverID) else {
                return
            }
            _ = applyLoadedConversation(cachedConversation)
            syncMessages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRunPolling(conversationServerID: String, runID: String, selectionToken: UUID) {
        runPollingTask?.cancel()
        runPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await pollRun(
                conversationServerID: conversationServerID,
                runID: runID,
                selectionToken: selectionToken
            )
        }
    }

    func pollRun(conversationServerID: String, runID: String, selectionToken: UUID) async {
        defer {
            if activeRunID == runID {
                activeRunID = nil
            }
            runPollingTask = nil
            isThinking = false
        }

        while !Task.isCancelled {
            do {
                try await loader.applyIncrementalSync()
                guard visibleSelectionToken == selectionToken else {
                    break
                }
                try await refreshVisibleConversation()
                let run = try await client.fetchRun(runID)
                isStreaming = run.status == .queued || run.status == .running
                if run.status == .completed || run.status == .failed || run.status == .cancelled {
                    break
                }
            } catch {
                errorMessage = error.localizedDescription
                break
            }

            do {
                try await Task.sleep(for: .seconds(1))
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
            syncMessages()
        } catch {
            errorMessage = error.localizedDescription
        }

        isStreaming = false
    }
}
