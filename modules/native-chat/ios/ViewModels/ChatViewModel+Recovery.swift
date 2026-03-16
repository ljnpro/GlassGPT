import Foundation

@MainActor
extension ChatViewModel {

    // MARK: - Recovery

    func recoverResponse(
        messageId: UUID,
        responseId: String,
        preferStreamingResume: Bool,
        visible: Bool = false
    ) {
        guard !apiKey.isEmpty else {
            return
        }

        guard let message = findMessage(byId: messageId) else { return }

        let session: ResponseSession
        if let existing = activeResponseSessions[messageId] {
            session = existing
        } else if let created = makeRecoverySession(for: message) {
            session = created
            registerSession(created, visible: visible)
        } else {
            return
        }

        if isSessionActive(session),
           session.task != nil,
           session.responseId == responseId {
            if visible {
                bindVisibleSession(messageID: messageId)
            }
            return
        }

        session.responseId = responseId
        setRecoveryPhase(.checkingStatus, for: session)
        session.isStreaming = false
        session.isThinking = false

        if visible {
            errorMessage = nil
            bindVisibleSession(messageID: messageId)
        }

        session.task?.cancel()

        session.task = Task { @MainActor in
            guard self.isSessionActive(session) else { return }

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: self.apiKey)

                switch result.status {
                case .completed:
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )
                    return

                case .failed, .incomplete, .unknown:
                    if visible {
                        self.errorMessage = result.errorMessage ?? "Response did not complete."
                    }
                    self.finishRecovery(
                        for: message,
                        session: session,
                        result: result,
                        fallbackText: self.recoveryFallbackText(for: message, session: session),
                        fallbackThinking: self.recoveryFallbackThinking(for: message, session: session)
                    )
                    return

                case .queued, .inProgress:
                    switch ChatSessionDecisions.recoveryResumeMode(
                    preferStreamingResume: preferStreamingResume,
                    usedBackgroundMode: message.usedBackgroundMode,
                    lastSequenceNumber: message.lastSequenceNumber
                    ) {
                    case .stream(let lastSeq):
                        await self.startStreamingRecovery(
                            session: session,
                            responseId: responseId,
                            lastSeq: lastSeq,
                            apiKey: self.apiKey
                        )
                        return

                    case .poll:
                        await self.pollResponseUntilTerminal(session: session, responseId: responseId)
                        return
                    }
                }
            } catch {
                if self.handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: visible
                ) {
                    return
                }

                #if DEBUG
                Loggers.recovery.debug("[Recovery] Status fetch failed for \(responseId): \(error.localizedDescription)")
                #endif
                await self.pollResponseUntilTerminal(session: session, responseId: responseId)
            }
        }
    }

    func startStreamingRecovery(
        session: ResponseSession,
        responseId: String,
        lastSeq: Int,
        apiKey: String,
        useDirectEndpoint: Bool = false
    ) async {
        let streamID = UUID()
        session.activeStreamID = streamID
        setRecoveryPhase(.streamResuming, for: session)
        session.isStreaming = true
        session.isThinking = false
        syncVisibleState(from: session)

        let stream = session.service.streamRecovery(
            responseId: responseId,
            startingAfter: lastSeq,
            apiKey: apiKey,
            useDirectBaseURL: useDirectEndpoint
        )

        var finishedFromStream = false
        var encounteredRecoverableFailure = false
        var receivedAnyRecoveryEvent = false
        var gatewayResumeTimedOut = false
        let gatewayFallbackTask: Task<Void, Never>? = {
            guard FeatureFlags.useCloudflareGateway, !useDirectEndpoint else {
                return nil
            }

            return Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                } catch {
                    return
                }

                guard self.isSessionActive(session), session.activeStreamID == streamID, !receivedAnyRecoveryEvent else {
                    return
                }

                gatewayResumeTimedOut = true
                session.service.cancelStream()
            }
        }()
        defer { gatewayFallbackTask?.cancel() }

        for await event in stream {
            guard isSessionActive(session), session.activeStreamID == streamID else { return }
            receivedAnyRecoveryEvent = true
            gatewayFallbackTask?.cancel()

            switch applyStreamEvent(event, to: session, animated: visibleSessionMessageID == session.messageID) {
            case .continued:
                break

            case .terminalCompleted:
                finishedFromStream = true
                finalizeSession(session)

            case .terminalIncomplete(let message):
                if visibleSessionMessageID == session.messageID {
                    errorMessage = message ?? "Response did not complete."
                }
                saveSessionNow(session)
                encounteredRecoverableFailure = true

            case .connectionLost:
                saveSessionNow(session)
                encounteredRecoverableFailure = true

            case .error(let error):
                if visibleSessionMessageID == session.messageID {
                    errorMessage = error.localizedDescription
                }
                saveSessionNow(session)
                encounteredRecoverableFailure = true
            }
        }

        guard isSessionActive(session), session.activeStreamID == streamID else { return }
        guard !finishedFromStream else { return }
        guard !Task.isCancelled else { return }

        session.isStreaming = false
        syncVisibleState(from: session)

        if ChatSessionDecisions.shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: FeatureFlags.useCloudflareGateway,
            useDirectEndpoint: useDirectEndpoint,
            gatewayResumeTimedOut: gatewayResumeTimedOut,
            receivedAnyRecoveryEvent: receivedAnyRecoveryEvent
        ) {
            #if DEBUG
            Loggers.recovery.debug("[Recovery] Gateway resume stalled for \(responseId); retrying direct")
            #endif
            await startStreamingRecovery(
                session: session,
                responseId: responseId,
                lastSeq: lastSeq,
                apiKey: apiKey,
                useDirectEndpoint: true
            )
            return
        }

        if ChatSessionDecisions.shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: encounteredRecoverableFailure,
            responseId: session.responseId
        ) {
            await pollResponseUntilTerminal(session: session, responseId: responseId)
        }
    }

    func pollResponseUntilTerminal(session: ResponseSession, responseId: String) async {
        guard !apiKey.isEmpty else { return }
        setRecoveryPhase(.pollingTerminal, for: session)

        let key = apiKey
        var attempts = 0
        let maxAttempts = 180
        var lastResult: OpenAIResponseFetchResult?
        var lastError: String?

        while !Task.isCancelled && attempts < maxAttempts {
            attempts += 1

            do {
                let result = try await session.service.fetchResponse(responseId: responseId, apiKey: key)
                lastResult = result

                switch result.status {
                case .queued, .inProgress:
                    #if DEBUG
                    if attempts <= 3 || attempts % 10 == 0 {
                        Loggers.recovery.debug("[Recovery] Response still \(result.status.rawValue), attempt \(attempts)/\(maxAttempts)")
                    }
                    #endif
                    do {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch {
                        return
                    }
                    continue

                case .completed, .incomplete, .failed, .unknown:
                    if let message = findMessage(byId: session.messageID) {
                        if result.status == .failed || result.status == .incomplete {
                            if visibleSessionMessageID == session.messageID {
                                errorMessage = result.errorMessage ?? "Response did not complete."
                            }
                        }
                        finishRecovery(
                            for: message,
                            session: session,
                            result: result,
                            fallbackText: recoveryFallbackText(for: message, session: session),
                            fallbackThinking: recoveryFallbackThinking(for: message, session: session)
                        )
                    }
                    return
                }
            } catch {
                if let message = findMessage(byId: session.messageID),
                   handleUnrecoverableRecoveryError(
                    error,
                    for: message,
                    responseId: responseId,
                    session: session,
                    visible: visibleSessionMessageID == session.messageID
                   ) {
                    return
                }

                lastError = error.localizedDescription
                #if DEBUG
                Loggers.recovery.debug("[Recovery] Poll error: \(lastError ?? "unknown"), attempt \(attempts)/\(maxAttempts)")
                #endif

                let delay: UInt64 = attempts < 10 ? 2_000_000_000 : 3_000_000_000
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }
        }

        guard !Task.isCancelled else { return }

        if let message = findMessage(byId: session.messageID) {
            if visibleSessionMessageID == session.messageID,
               let lastError,
               !lastError.isEmpty {
                errorMessage = lastError
            }
            finishRecovery(
                for: message,
                session: session,
                result: lastResult,
                fallbackText: recoveryFallbackText(for: message, session: session),
                fallbackThinking: recoveryFallbackThinking(for: message, session: session)
            )
        }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Finished with fallback after \(attempts) attempts. Last error: \(lastError ?? "none")")
        #endif
    }

    func recoverIncompleteMessages() async {
        guard !apiKey.isEmpty else { return }

        await cleanupStaleDrafts()

        let fetchedMessages: [Message]
        do {
            fetchedMessages = try draftRepository.fetchRecoverableDrafts()
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch recoverable drafts: \(error.localizedDescription)")
            return
        }

        let activeDraftID = activeIncompleteAssistantDraft()?.id
        let currentConversationID = currentConversation?.id
        let incompleteMessages = fetchedMessages.filter {
            $0.id != activeDraftID && $0.conversation?.id != currentConversationID
        }
        guard !incompleteMessages.isEmpty else { return }

        #if DEBUG
        Loggers.recovery.debug("[Recovery] Found \(incompleteMessages.count) incomplete message(s) to recover")
        #endif

        for message in incompleteMessages {
            guard let responseId = message.responseId else { continue }
            recoverSingleMessage(message: message, responseId: responseId, visible: false)
        }
    }

    func cleanupStaleDrafts() async {
        let staleThreshold = Date().addingTimeInterval(-24 * 60 * 60)
        let staleMessages: [Message]

        do {
            staleMessages = try draftRepository.fetchIncompleteDrafts()
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch stale drafts: \(error.localizedDescription)")
            return
        }

        var cleanedCount = 0

        for message in staleMessages {
            guard message.createdAt < staleThreshold else { continue }

            if message.content.isEmpty && message.responseId == nil {
                conversationRepository.delete(message)
                cleanedCount += 1
            } else {
                message.isComplete = true
                if message.content.isEmpty {
                    message.content = "[Response interrupted. Please try again.]"
                }
                cleanedCount += 1
            }
        }

        if cleanedCount > 0 {
            saveContextIfPossible("cleanupStaleDrafts")
            #if DEBUG
            Loggers.recovery.debug("[Recovery] Cleaned up \(cleanedCount) stale draft(s)")
            #endif
        }
    }

    func resendOrphanedDrafts() async {
        guard !apiKey.isEmpty else { return }

        let orphanedDrafts: [Message]
        do {
            orphanedDrafts = try draftRepository.fetchOrphanedDrafts()
        } catch {
            Loggers.recovery.error("[Recovery] Failed to fetch orphaned drafts: \(error.localizedDescription)")
            return
        }

        let draftsToResend = orphanedDrafts.filter { $0.role == .assistant && $0.content.isEmpty }

        #if DEBUG
        if !draftsToResend.isEmpty {
            Loggers.recovery.debug("[Recovery] Found \(draftsToResend.count) orphaned draft(s) to resend")
        }
        #endif

        let currentConversationID = currentConversation?.id

        for draft in draftsToResend {
            guard let conversation = draft.conversation else {
                conversationRepository.delete(draft)
                saveContextIfPossible("resendOrphanedDrafts.deleteDetachedDraft")
                continue
            }

            if let currentConversationID, conversation.id != currentConversationID {
                continue
            }

            let userMessages = conversation.messages
                .filter { $0.role == .user }
                .sorted { $0.createdAt < $1.createdAt }

            guard userMessages.last != nil else {
                conversationRepository.delete(draft)
                saveContextIfPossible("resendOrphanedDrafts.deleteDraftWithoutUserMessage")
                continue
            }

            #if DEBUG
            Loggers.recovery.debug("[Recovery] Resending request for orphaned draft in conversation: \(conversation.title)")
            #endif

            currentConversation = conversation
            messages = visibleMessages(for: conversation)
                .filter { $0.id != draft.id }

            applyConversationConfiguration(from: conversation)

            if let idx = conversation.messages.firstIndex(where: { $0.id == draft.id }) {
                conversation.messages.remove(at: idx)
            }

            conversationRepository.delete(draft)
            saveContextIfPossible("resendOrphanedDrafts.deleteBeforeRestart")

            let newDraft = Message(
                role: .assistant,
                content: "",
                thinking: nil,
                lastSequenceNumber: nil,
                usedBackgroundMode: backgroundModeEnabled,
                isComplete: false
            )
            newDraft.conversation = currentConversation
            currentConversation?.messages.append(newDraft)
            saveContextIfPossible("resendOrphanedDrafts.insertReplacementDraft")

            guard let session = makeStreamingSession(for: newDraft) else {
                errorMessage = "Failed to restart orphaned draft."
                return
            }

            registerSession(session, visible: true)
            session.isStreaming = true
            session.isThinking = true
            setRecoveryPhase(.idle, for: session)
            syncVisibleState(from: session)
            errorMessage = nil

            #if DEBUG
            Loggers.recovery.debug("[Recovery] Starting resend stream for conversation: \(conversation.title), messages count: \(messages.count)")
            #endif

            startStreamingRequest(for: session)
            return
        }
    }

    func recoverIncompleteMessagesInCurrentConversation() async {
        guard !apiKey.isEmpty else { return }
        guard let conversation = currentConversation else { return }

        let incompleteMessages = conversation.messages.filter {
            $0.role == .assistant && !$0.isComplete && $0.responseId != nil
        }

        guard !incompleteMessages.isEmpty else { return }

        let sortedMessages = incompleteMessages.sorted { $0.createdAt < $1.createdAt }

        if let activeMessage = sortedMessages.last,
           let responseId = activeMessage.responseId {
            recoverResponse(
                messageId: activeMessage.id,
                responseId: responseId,
                preferStreamingResume: activeMessage.usedBackgroundMode,
                visible: true
            )
        }

        for message in sortedMessages.dropLast() {
            guard let responseId = message.responseId else { continue }
            recoverSingleMessage(message: message, responseId: responseId, visible: false)
        }
    }

    func recoverSingleMessage(message: Message, responseId: String, visible: Bool) {
        recoverResponse(
            messageId: message.id,
            responseId: responseId,
            preferStreamingResume: message.usedBackgroundMode,
            visible: visible
        )
    }

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
