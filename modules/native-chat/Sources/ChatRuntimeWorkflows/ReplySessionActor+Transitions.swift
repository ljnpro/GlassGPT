import ChatDomain
import ChatRuntimeModel
import Foundation
import os

private let runtimeSignposter = OSSignposter(subsystem: "GlassGPT", category: "runtime")

public extension ReplySessionActor {
    /// Applies a transition to the session state and returns the updated state.
    ///
    /// Content transitions (text, thinking, tool calls, citations) are handled inline.
    /// Lifecycle transitions are delegated to ``applyLifecycleTransition(_:)``.
    /// - Parameter transition: The transition to apply.
    /// - Returns: The updated runtime state.
    @discardableResult
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func apply(_ transition: ReplyRuntimeTransition) -> ReplyRuntimeState {
        let signpostID = runtimeSignposter.makeSignpostID()
        let signpostState = runtimeSignposter.beginInterval("ApplyTransition", id: signpostID)
        defer { runtimeSignposter.endInterval("ApplyTransition", signpostState) }

        switch transition {
        case .beginSubmitting:
            state.lifecycle = .preparingInput
            state.isThinking = false
            activeStreamID = nil

        case .beginUploadingAttachments:
            state.lifecycle = .uploadingAttachments
            state.isThinking = false
            activeStreamID = nil

        case let .beginStreaming(streamID, route):
            activeStreamID = streamID
            if let cursor = state.cursor {
                state.lifecycle = .streaming(
                    StreamCursor(
                        responseID: cursor.responseID,
                        lastSequenceNumber: cursor.lastSequenceNumber,
                        route: route
                    )
                )
            } else {
                state.lifecycle = .preparingInput
            }
            state.isThinking = false

        case let .recordResponseCreated(responseID, route):
            let cursor = StreamCursor(
                responseID: responseID,
                lastSequenceNumber: state.lastSequenceNumber,
                route: route
            )
            switch state.lifecycle {
            case .recoveringStream:
                state.lifecycle = .recoveringStream(cursor)
            case let .recoveringStatus(ticket):
                state.lifecycle = .recoveringStatus(
                    DetachedRecoveryTicket(
                        assistantReplyID: ticket.assistantReplyID,
                        messageID: ticket.messageID,
                        conversationID: ticket.conversationID,
                        responseID: responseID,
                        lastSequenceNumber: ticket.lastSequenceNumber,
                        usedBackgroundMode: ticket.usedBackgroundMode,
                        route: route
                    )
                )
            case let .recoveringPoll(ticket):
                state.lifecycle = .recoveringPoll(
                    DetachedRecoveryTicket(
                        assistantReplyID: ticket.assistantReplyID,
                        messageID: ticket.messageID,
                        conversationID: ticket.conversationID,
                        responseID: responseID,
                        lastSequenceNumber: ticket.lastSequenceNumber,
                        usedBackgroundMode: ticket.usedBackgroundMode,
                        route: route
                    )
                )
            case .idle, .preparingInput, .uploadingAttachments, .streaming, .detached, .finalizing, .completed, .failed:
                state.lifecycle = .streaming(cursor)
            }

        case let .recordSequenceUpdate(sequence):
            updateCursor(lastSequenceNumber: sequence)

        case let .appendText(delta):
            state.buffer.text += delta
            state.isThinking = false

        case let .appendThinking(delta):
            state.buffer.thinking += delta

        case let .setThinking(isThinking):
            state.isThinking = isThinking

        case let .startToolCall(id, type):
            guard !state.buffer.toolCalls.contains(where: { $0.id == id }) else {
                return state
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
                return state
            }
            state.buffer.toolCalls[index].status = status

        case let .appendToolCode(id, delta):
            guard let index = state.buffer.toolCalls.firstIndex(where: { $0.id == id }) else {
                return state
            }
            let existing = state.buffer.toolCalls[index].code ?? ""
            state.buffer.toolCalls[index].code = existing + delta

        case let .setToolCode(id, code):
            guard let index = state.buffer.toolCalls.firstIndex(where: { $0.id == id }) else {
                return state
            }
            state.buffer.toolCalls[index].code = code

        case let .addCitation(citation):
            guard !state.buffer.citations.contains(where: { $0.id == citation.id }) else {
                return state
            }
            state.buffer.citations.append(citation)

        case let .addFilePathAnnotation(annotation):
            guard !state.buffer.filePathAnnotations.contains(where: { $0.fileId == annotation.fileId }) else {
                return state
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
            return applyLifecycleTransition(transition)
        }

        return state
    }
}
