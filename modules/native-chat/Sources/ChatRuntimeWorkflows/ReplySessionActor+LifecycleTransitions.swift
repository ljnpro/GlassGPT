import ChatRuntimeModel
import Foundation

extension ReplySessionActor {
    func applyLifecycleTransition(_ transition: ReplyRuntimeTransition) -> ReplyRuntimeState {
        switch transition {
        case .beginRecoveryStatus(let responseID, let lastSequenceNumber, let usedBackgroundMode, let route):
            activeStreamID = nil
            state.lifecycle = .recoveringStatus(
                DetachedRecoveryTicket(
                    assistantReplyID: state.assistantReplyID,
                    messageID: state.messageID,
                    conversationID: state.conversationID,
                    responseID: responseID,
                    lastSequenceNumber: lastSequenceNumber ?? state.lastSequenceNumber,
                    usedBackgroundMode: usedBackgroundMode,
                    route: route
                )
            )
            state.isThinking = false

        case .beginRecoveryStream(let streamID):
            activeStreamID = streamID
            let cursor = state.cursor ?? StreamCursor(
                responseID: "",
                lastSequenceNumber: nil,
                route: .gateway
            )
            state.lifecycle = .recoveringStream(cursor)
            state.isThinking = false

        case .beginRecoveryPoll:
            activeStreamID = nil
            let usedBackgroundMode: Bool
            switch state.lifecycle {
            case .recoveringStatus(let ticket), .recoveringPoll(let ticket), .detached(let ticket):
                usedBackgroundMode = ticket.usedBackgroundMode
            case .idle, .preparingInput, .uploadingAttachments, .streaming, .recoveringStream, .finalizing, .completed, .failed:
                usedBackgroundMode = false
            }
            if let cursor = state.cursor {
                state.lifecycle = .recoveringPoll(
                    DetachedRecoveryTicket(
                        assistantReplyID: state.assistantReplyID,
                        messageID: state.messageID,
                        conversationID: state.conversationID,
                        responseID: cursor.responseID,
                        lastSequenceNumber: cursor.lastSequenceNumber,
                        usedBackgroundMode: usedBackgroundMode,
                        route: cursor.route
                    )
                )
            }
            state.isThinking = false

        case .detachForBackground(let usedBackgroundMode):
            activeStreamID = nil
            if let cursor = state.cursor {
                state.lifecycle = .detached(
                    DetachedRecoveryTicket(
                        assistantReplyID: state.assistantReplyID,
                        messageID: state.messageID,
                        conversationID: state.conversationID,
                        responseID: cursor.responseID,
                        lastSequenceNumber: cursor.lastSequenceNumber,
                        usedBackgroundMode: usedBackgroundMode,
                        route: cursor.route
                    )
                )
            } else {
                state.lifecycle = .failed(nil)
            }
            state.isThinking = false

        case .cancelStreaming:
            activeStreamID = nil
            state.lifecycle = .idle
            state.isThinking = false

        case .beginFinalizing:
            state.lifecycle = .finalizing

        case .markCompleted:
            activeStreamID = nil
            state.lifecycle = .completed
            state.isThinking = false

        case .markFailed(let message):
            activeStreamID = nil
            state.lifecycle = .failed(message)
            state.isThinking = false

        case .beginSubmitting, .beginUploadingAttachments, .beginStreaming, .recordResponseCreated, .recordSequenceUpdate, .appendText, .appendThinking, .setThinking, .startToolCall, .setToolCallStatus, .appendToolCode, .setToolCode, .addCitation, .addFilePathAnnotation, .mergeTerminalPayload:
            break
        }

        return state
    }

    func updateCursor(lastSequenceNumber sequence: Int) {
        guard let cursor = state.cursor else {
            return
        }

        let nextSequence: Int
        if let currentSequence = cursor.lastSequenceNumber {
            nextSequence = max(currentSequence, sequence)
        } else {
            nextSequence = sequence
        }

        let updatedCursor = StreamCursor(
            responseID: cursor.responseID,
            lastSequenceNumber: nextSequence,
            route: cursor.route
        )

        switch state.lifecycle {
        case .streaming:
            state.lifecycle = .streaming(updatedCursor)
        case .recoveringStream:
            state.lifecycle = .recoveringStream(updatedCursor)
        case .recoveringStatus(let ticket):
            state.lifecycle = .recoveringStatus(
                DetachedRecoveryTicket(
                    assistantReplyID: ticket.assistantReplyID,
                    messageID: ticket.messageID,
                    conversationID: ticket.conversationID,
                    responseID: ticket.responseID,
                    lastSequenceNumber: nextSequence,
                    usedBackgroundMode: ticket.usedBackgroundMode,
                    route: ticket.route
                )
            )
        case .recoveringPoll(let ticket):
            state.lifecycle = .recoveringPoll(
                DetachedRecoveryTicket(
                    assistantReplyID: ticket.assistantReplyID,
                    messageID: ticket.messageID,
                    conversationID: ticket.conversationID,
                    responseID: ticket.responseID,
                    lastSequenceNumber: nextSequence,
                    usedBackgroundMode: ticket.usedBackgroundMode,
                    route: ticket.route
                )
            )
        case .detached(let ticket):
            state.lifecycle = .detached(
                DetachedRecoveryTicket(
                    assistantReplyID: ticket.assistantReplyID,
                    messageID: ticket.messageID,
                    conversationID: ticket.conversationID,
                    responseID: ticket.responseID,
                    lastSequenceNumber: nextSequence,
                    usedBackgroundMode: ticket.usedBackgroundMode,
                    route: ticket.route
                )
            )
        case .idle, .preparingInput, .uploadingAttachments, .finalizing, .completed, .failed:
            break
        }
    }
}
