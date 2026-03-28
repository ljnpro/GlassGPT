import ChatProjectionPersistence
import Foundation

package extension BackendMessageSurface {
    init(message: Message) {
        id = message.id
        role = message.role
        content = message.content
        thinking = message.thinking
        imageData = message.imageData
        isComplete = message.isComplete
        annotations = message.annotations
        toolCalls = message.toolCalls
        fileAttachments = message.fileAttachments
        filePathAnnotations = message.filePathAnnotations
        agentTrace = message.agentTrace
        payloadRenderDigest = message.payloadRenderDigest
    }
}
