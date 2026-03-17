import Foundation

@MainActor
extension ChatScreenStore {
    func findMessage(byId id: UUID) -> Message? {
        if let msg = messages.first(where: { $0.id == id }) {
            return msg
        }

        if let draft = draftMessage, draft.id == id {
            return draft
        }

        do {
            return try conversationRepository.fetchMessage(id: id)
        } catch {
            Loggers.persistence.error("[findMessage] \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func detachBackgroundResponseIfPossible(reason: String) -> Bool {
        guard
            let session = currentVisibleSession,
            let draft = draftMessage,
            ChatSessionDecisions.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: draft.usedBackgroundMode,
                responseId: draft.responseId
            )
        else {
            return false
        }

        saveSessionNow(session)
        errorMessage = nil
        detachVisibleSessionBinding()
        endBackgroundTask()

        #if DEBUG
        Loggers.chat.debug("[Detach] Detached background response for \(reason)")
        #endif

        return true
    }
}
