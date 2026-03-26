import ChatDomain
import ChatRuntimeModel

extension ReplySessionActor {
    func applyTextBufferTransition(_ transition: ReplyRuntimeTransition) {
        switch transition {
        case let .appendText(delta):
            promoteRecoveryLifecycleIfNeededForProgress()
            state.buffer.text += delta

        case let .replaceText(text):
            promoteRecoveryLifecycleIfNeededForProgress()
            state.buffer.text = text

        case let .appendThinking(delta):
            promoteRecoveryLifecycleIfNeededForProgress()
            state.buffer.thinking += delta

        case let .setThinking(isThinking):
            if isThinking {
                promoteRecoveryLifecycleIfNeededForProgress()
            }
            state.isThinking = isThinking

        default:
            break
        }
    }

    func applyToolTransition(_ transition: ReplyRuntimeTransition) {
        switch transition {
        case let .startToolCall(id, type):
            promoteRecoveryLifecycleIfNeededForProgress()
            guard !state.buffer.toolCalls.contains(where: { $0.id == id }) else {
                return
            }
            state.buffer.toolCalls.append(
                ToolCallInfo(
                    id: id,
                    type: type,
                    status: .inProgress
                )
            )

        case let .setToolCallStatus(id, status):
            promoteRecoveryLifecycleIfNeededForProgress()
            guard let index = state.buffer.toolCalls.firstIndex(where: { $0.id == id }) else {
                return
            }
            state.buffer.toolCalls[index].status = status

        case let .appendToolCode(id, delta):
            promoteRecoveryLifecycleIfNeededForProgress()
            guard let index = state.buffer.toolCalls.firstIndex(where: { $0.id == id }) else {
                return
            }
            let existing = state.buffer.toolCalls[index].code ?? ""
            state.buffer.toolCalls[index].code = existing + delta

        case let .setToolCode(id, code):
            promoteRecoveryLifecycleIfNeededForProgress()
            guard let index = state.buffer.toolCalls.firstIndex(where: { $0.id == id }) else {
                return
            }
            state.buffer.toolCalls[index].code = code

        case let .addCitation(citation):
            promoteRecoveryLifecycleIfNeededForProgress()
            guard !state.buffer.citations.contains(where: { $0.id == citation.id }) else {
                return
            }
            state.buffer.citations.append(citation)

        case let .addFilePathAnnotation(annotation):
            promoteRecoveryLifecycleIfNeededForProgress()
            guard !state.buffer.filePathAnnotations.contains(where: { $0.fileId == annotation.fileId }) else {
                return
            }
            state.buffer.filePathAnnotations.append(annotation)

        case let .mergeTerminalPayload(text, thinking, filePathAnnotations):
            promoteRecoveryLifecycleIfNeededForProgress()
            applyTerminalPayload(
                text: text,
                thinking: thinking,
                filePathAnnotations: filePathAnnotations
            )

        case let .beginAnswering(text, replace):
            promoteRecoveryLifecycleIfNeededForProgress()
            applyAnsweringTransition(text: text, replace: replace)

        default:
            break
        }
    }

    private func applyTerminalPayload(
        text: String,
        thinking: String?,
        filePathAnnotations: [FilePathAnnotation]?
    ) {
        if !text.isEmpty {
            state.buffer.text = text
        }
        if let thinking, !thinking.isEmpty {
            state.buffer.thinking = thinking
        }
        if let filePathAnnotations, !filePathAnnotations.isEmpty {
            state.buffer.filePathAnnotations = filePathAnnotations
        }
        completeActiveToolCalls()
        state.isThinking = false
    }

    private func applyAnsweringTransition(text: String, replace: Bool) {
        if replace {
            state.buffer.text = text
        } else {
            state.buffer.text += text
        }
        completeActiveToolCalls()
        state.isThinking = false
    }

    private func completeActiveToolCalls() {
        for index in state.buffer.toolCalls.indices where state.buffer.toolCalls[index].status != .completed {
            state.buffer.toolCalls[index].status = .completed
        }
    }

    private func promoteRecoveryLifecycleIfNeededForProgress() {
        state.pendingRecoveryRestart = false
        switch state.lifecycle {
        case .recoveringStatus, .recoveringStream, .recoveringPoll:
            let cursor = state.cursor ?? StreamCursor(
                responseID: "",
                lastSequenceNumber: nil,
                route: .gateway
            )
            state.lifecycle = .streaming(cursor)
        case .idle, .preparingInput, .uploadingAttachments, .streaming, .detached, .finalizing, .completed, .failed:
            break
        }
    }
}
