import ChatRuntimeModel

extension ReplySessionActor {
    func applySubmissionTransition(_ transition: ReplyRuntimeTransition) {
        switch transition {
        case .beginSubmitting:
            state.lifecycle = .preparingInput
            state.isThinking = false
            state.recoveryUsesBackgroundMode = nil
            state.pendingRecoveryRestart = false
            activeStreamID = nil

        case .beginUploadingAttachments:
            state.lifecycle = .uploadingAttachments
            state.isThinking = false
            state.recoveryUsesBackgroundMode = nil
            state.pendingRecoveryRestart = false
            activeStreamID = nil

        case let .beginStreaming(streamID, route):
            activeStreamID = streamID
            state.buffer = ReplyBuffer(attachments: state.buffer.attachments)
            let shouldPreserveRecoveryBackgroundSemantics = state.isRecovering || state.pendingRecoveryRestart
            if !shouldPreserveRecoveryBackgroundSemantics {
                state.recoveryUsesBackgroundMode = nil
            }
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
            // A recovery restart should remain visibly active until the restarted
            // stream proves liveness with fresh progress.
            state.isThinking = state.pendingRecoveryRestart

        default:
            break
        }
    }
}
