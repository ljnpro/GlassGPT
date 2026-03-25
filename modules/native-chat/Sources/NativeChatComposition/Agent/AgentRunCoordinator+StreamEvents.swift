import ChatDomain
import OpenAITransport

extension AgentRunCoordinator {
    func applyVisibleStreamEvent(_ event: StreamEvent) throws {
        if try applyLifecycleEvent(event) {
            return
        }
        if applyToolEvent(event) {
            return
        }
        applyAnnotationEvent(event)
    }

    private func applyLifecycleEvent(_ event: StreamEvent) throws -> Bool {
        switch event {
        case let .textDelta(delta):
            state.currentStreamingText += delta
        case let .replaceText(text):
            state.currentStreamingText = text
        case .thinkingStarted:
            state.isThinking = true
        case let .thinkingDelta(delta):
            state.isThinking = true
            state.currentThinkingText += delta
        case .thinkingFinished:
            state.isThinking = false
        case let .responseCreated(responseID):
            updateRoleResponseID(responseID, for: .leader)
            state.draftMessage?.responseId = responseID
        case let .sequenceUpdate(sequenceNumber):
            state.draftMessage?.lastSequenceNumber = sequenceNumber
        case let .completed(text, thinking, fileAnnotations):
            applyCompletionSnapshot(text: text, thinking: thinking, fileAnnotations: fileAnnotations)
        case let .incomplete(text, thinking, fileAnnotations, message):
            applyCompletionSnapshot(text: text, thinking: thinking, fileAnnotations: fileAnnotations)
            throw AgentRunFailure.incomplete(message ?? "Agent synthesis was incomplete.")
        case .connectionLost:
            throw AgentRunFailure.incomplete("Agent synthesis lost its connection.")
        case let .error(error):
            throw AgentRunFailure.invalidResponse(error.localizedDescription)
        default:
            return false
        }

        return true
    }

    private func applyToolEvent(_ event: StreamEvent) -> Bool {
        switch event {
        case let .webSearchStarted(id):
            startToolCall(id: id, type: .webSearch)
        case let .webSearchSearching(id):
            setToolCallStatus(id: id, status: .searching)
        case let .webSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed)
        case let .codeInterpreterStarted(id):
            startToolCall(id: id, type: .codeInterpreter)
        case let .codeInterpreterInterpreting(id):
            setToolCallStatus(id: id, status: .interpreting)
        case let .codeInterpreterCodeDelta(id, delta):
            appendToolCode(id: id, delta: delta)
        case let .codeInterpreterCodeDone(id, code):
            setToolCode(id: id, code: code)
        case let .codeInterpreterCompleted(id):
            setToolCallStatus(id: id, status: .completed)
        case let .fileSearchStarted(id):
            startToolCall(id: id, type: .fileSearch)
        case let .fileSearchSearching(id):
            setToolCallStatus(id: id, status: .fileSearching)
        case let .fileSearchCompleted(id):
            setToolCallStatus(id: id, status: .completed)
        default:
            return false
        }

        return true
    }

    private func applyAnnotationEvent(_ event: StreamEvent) {
        switch event {
        case let .annotationAdded(annotation):
            state.liveCitations.append(annotation)
        case let .filePathAnnotationAdded(annotation):
            state.liveFilePathAnnotations.append(annotation)
        default:
            break
        }
    }

    private func applyCompletionSnapshot(
        text: String,
        thinking: String?,
        fileAnnotations: [FilePathAnnotation]?
    ) {
        state.currentStreamingText = text
        if let thinking {
            state.currentThinkingText = thinking
        }
        if let fileAnnotations {
            state.liveFilePathAnnotations = fileAnnotations
        }
    }

    private func startToolCall(id: String, type: ToolCallType) {
        guard !state.activeToolCalls.contains(where: { $0.id == id }) else { return }
        state.activeToolCalls.append(
            ToolCallInfo(
                id: id,
                type: type,
                status: .inProgress
            )
        )
    }

    private func setToolCallStatus(id: String, status: ToolCallStatus) {
        guard let index = state.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        state.activeToolCalls[index].status = status
    }

    private func appendToolCode(id: String, delta: String) {
        guard let index = state.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        state.activeToolCalls[index].code = (state.activeToolCalls[index].code ?? "") + delta
    }

    private func setToolCode(id: String, code: String) {
        guard let index = state.activeToolCalls.firstIndex(where: { $0.id == id }) else { return }
        state.activeToolCalls[index].code = code
    }
}
