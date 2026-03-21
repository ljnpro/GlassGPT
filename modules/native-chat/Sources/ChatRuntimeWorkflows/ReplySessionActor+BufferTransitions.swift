import ChatDomain
import ChatRuntimeModel

extension ReplySessionActor {
    func applyTextBufferTransition(_ transition: ReplyRuntimeTransition) {
        switch transition {
        case let .appendText(delta):
            state.buffer.text += delta
            state.isThinking = false

        case let .appendThinking(delta):
            state.buffer.thinking += delta

        case let .setThinking(isThinking):
            state.isThinking = isThinking

        default:
            break
        }
    }

    func applyToolTransition(_ transition: ReplyRuntimeTransition) {
        switch transition {
        case let .startToolCall(id, type):
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
            guard let index = state.buffer.toolCalls.firstIndex(where: { $0.id == id }) else {
                return
            }
            state.buffer.toolCalls[index].status = status

        case let .appendToolCode(id, delta):
            guard let index = state.buffer.toolCalls.firstIndex(where: { $0.id == id }) else {
                return
            }
            let existing = state.buffer.toolCalls[index].code ?? ""
            state.buffer.toolCalls[index].code = existing + delta

        case let .setToolCode(id, code):
            guard let index = state.buffer.toolCalls.firstIndex(where: { $0.id == id }) else {
                return
            }
            state.buffer.toolCalls[index].code = code

        case let .addCitation(citation):
            guard !state.buffer.citations.contains(where: { $0.id == citation.id }) else {
                return
            }
            state.buffer.citations.append(citation)

        case let .addFilePathAnnotation(annotation):
            guard !state.buffer.filePathAnnotations.contains(where: { $0.fileId == annotation.fileId }) else {
                return
            }
            state.buffer.filePathAnnotations.append(annotation)

        case let .mergeTerminalPayload(text, thinking, filePathAnnotations):
            if !text.isEmpty {
                state.buffer.text = text
            }
            if let thinking, !thinking.isEmpty {
                state.buffer.thinking = thinking
            }
            if let filePathAnnotations, !filePathAnnotations.isEmpty {
                state.buffer.filePathAnnotations = filePathAnnotations
            }

        default:
            break
        }
    }
}
