import ChatRuntimeModel

extension ReplySessionActor {
    func applyStreamMetadataTransition(_ transition: ReplyRuntimeTransition) {
        switch transition {
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

        default:
            break
        }
    }
}
