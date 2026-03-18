import ChatDomain
import ChatRuntimeModel
import Foundation

public enum ReplyRuntimeTransition: Sendable, Equatable {
    case beginSubmitting
    case beginUploadingAttachments
    case beginStreaming(streamID: UUID, route: OpenAITransportRoute)
    case recordResponseCreated(String, route: OpenAITransportRoute)
    case recordSequenceUpdate(Int)
    case appendText(String)
    case appendThinking(String)
    case setThinking(Bool)
    case startToolCall(id: String, type: ToolCallType)
    case setToolCallStatus(id: String, status: ToolCallStatus)
    case appendToolCode(id: String, delta: String)
    case setToolCode(id: String, code: String)
    case addCitation(URLCitation)
    case addFilePathAnnotation(FilePathAnnotation)
    case mergeTerminalPayload(text: String, thinking: String?, filePathAnnotations: [FilePathAnnotation]?)
    case beginRecoveryStatus(
        responseID: String,
        lastSequenceNumber: Int?,
        usedBackgroundMode: Bool,
        route: OpenAITransportRoute
    )
    case beginRecoveryStream(streamID: UUID)
    case beginRecoveryPoll
    case detachForBackground(usedBackgroundMode: Bool)
    case cancelStreaming
    case beginFinalizing
    case markCompleted
    case markFailed(String?)
}
