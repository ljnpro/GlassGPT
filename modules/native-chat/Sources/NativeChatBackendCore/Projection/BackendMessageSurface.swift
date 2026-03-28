import ChatDomain
import Foundation

/// View-facing projection of one cached backend message, decoupled from the underlying SwiftData entity.
package struct BackendMessageSurface: Equatable, Identifiable {
    package let id: UUID
    package let role: MessageRole
    package let content: String
    package let thinking: String?
    package let imageData: Data?
    package let isComplete: Bool
    package let annotations: [URLCitation]
    package let toolCalls: [ToolCallInfo]
    package let fileAttachments: [FileAttachment]
    package let filePathAnnotations: [FilePathAnnotation]
    package let agentTrace: AgentTurnTrace?
    package let payloadRenderDigest: String

    package var roleRawValue: String {
        role.rawValue
    }
}
