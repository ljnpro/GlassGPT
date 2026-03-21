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
    func apply(_ transition: ReplyRuntimeTransition) -> ReplyRuntimeState {
        let signpostID = runtimeSignposter.makeSignpostID()
        let signpostState = runtimeSignposter.beginInterval("ApplyTransition", id: signpostID)
        defer { runtimeSignposter.endInterval("ApplyTransition", signpostState) }

        switch transition {
        case .beginSubmitting:
            applySubmissionTransition(transition)

        case .beginUploadingAttachments:
            applySubmissionTransition(transition)

        case let .beginStreaming(streamID, route):
            applySubmissionTransition(.beginStreaming(streamID: streamID, route: route))

        case let .recordResponseCreated(responseID, route):
            applyStreamMetadataTransition(.recordResponseCreated(responseID, route: route))

        case let .recordSequenceUpdate(sequence):
            applyStreamMetadataTransition(.recordSequenceUpdate(sequence))

        case let .appendText(delta):
            applyTextBufferTransition(.appendText(delta))

        case let .replaceText(text):
            applyTextBufferTransition(.replaceText(text))

        case let .appendThinking(delta):
            applyTextBufferTransition(.appendThinking(delta))

        case let .beginAnswering(text, replace):
            applyToolTransition(.beginAnswering(text: text, replace: replace))

        case let .setThinking(isThinking):
            applyTextBufferTransition(.setThinking(isThinking))

        case let .startToolCall(id, type):
            applyToolTransition(.startToolCall(id: id, type: type))

        case let .setToolCallStatus(id, status):
            applyToolTransition(.setToolCallStatus(id: id, status: status))

        case let .appendToolCode(id, delta):
            applyToolTransition(.appendToolCode(id: id, delta: delta))

        case let .setToolCode(id, code):
            applyToolTransition(.setToolCode(id: id, code: code))

        case let .addCitation(citation):
            applyToolTransition(.addCitation(citation))

        case let .addFilePathAnnotation(annotation):
            applyToolTransition(.addFilePathAnnotation(annotation))

        case let .mergeTerminalPayload(text, thinking, filePathAnnotations):
            applyToolTransition(.mergeTerminalPayload(text: text, thinking: thinking, filePathAnnotations: filePathAnnotations))

        default:
            return applyLifecycleTransition(transition)
        }

        return state
    }
}
