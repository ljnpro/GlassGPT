import ChatRuntimeModel

extension ReplySessionActor {
    func applySubmissionTransition(_ transition: ReplyRuntimeTransition) {
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

        default:
            break
        }
    }
}
