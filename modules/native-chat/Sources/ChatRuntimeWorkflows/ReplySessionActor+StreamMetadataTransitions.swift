import ChatRuntimeModel

extension ReplySessionActor {
    func applyStreamMetadataTransition(_ transition: ReplyRuntimeTransition) {
        switch transition {
        case let .recordResponseCreated(responseID, route):
            state.pendingRecoveryRestart = false
            let recoveryUsesBackgroundMode: Bool? = switch state.lifecycle {
            case let .recoveringStatus(ticket), let .recoveringPoll(ticket), let .detached(ticket):
                ticket.usedBackgroundMode
            case .recoveringStream, .streaming:
                state.recoveryUsesBackgroundMode
            case .idle, .preparingInput, .uploadingAttachments, .finalizing, .completed, .failed:
                state.recoveryUsesBackgroundMode
            }
            let cursor = StreamCursor(
                responseID: responseID,
                lastSequenceNumber: state.lastSequenceNumber,
                route: route
            )
            switch state.lifecycle {
            case .recoveringStream,
                 .recoveringStatus,
                 .recoveringPoll:
                state.recoveryUsesBackgroundMode = recoveryUsesBackgroundMode
                // The recovery banner should disappear as soon as the resumed stream
                // proves liveness with a fresh response id.
                state.lifecycle = .streaming(cursor)
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
