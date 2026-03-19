import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation

@MainActor
func recoveryFallbackText(
    for message: Message,
    session: ReplySession? = nil,
    runtimeState: ReplyRuntimeState?,
    visibleSessionMessageID: UUID?,
    currentStreamingText: String
) -> String {
    if session != nil,
       let runtimeState,
       !runtimeState.buffer.text.isEmpty {
        return runtimeState.buffer.text
    }

    if message.id == visibleSessionMessageID, !currentStreamingText.isEmpty {
        return currentStreamingText
    }

    return message.content
}

func interruptedResponseFallbackText(_ baseText: String) -> String {
    let interruptionNotice = "Response interrupted because the app was closed before completion."
    let trimmedBaseText = baseText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedBaseText.isEmpty else {
        return interruptionNotice
    }

    if trimmedBaseText.contains(interruptionNotice) {
        return trimmedBaseText
    }

    return "\(trimmedBaseText)\n\n\(interruptionNotice)"
}
