import BackendAuth
import ChatDomain
import ChatPresentation
import Foundation

/// Shared derived display state used by backend conversation controllers.
@MainActor
package protocol BackendConversationDisplayState: AnyObject {
    var messages: [BackendMessageSurface] { get }
    var currentStreamingText: String { get }
    var currentThinkingText: String { get }
    var activeToolCalls: [ToolCallInfo] { get }
    var liveCitations: [URLCitation] { get }
    var liveFilePathAnnotations: [FilePathAnnotation] { get }
    var serviceTier: ServiceTier { get set }
    var isThinking: Bool { get }
    var isConversationRunActive: Bool { get }
    var sessionStore: BackendSessionStore { get }

    func persistVisibleConfiguration()
}

@MainActor
package extension BackendConversationDisplayState {
    /// The in-progress assistant draft message, if one exists in the visible transcript.
    var draftMessage: BackendMessageSurface? {
        messages.last(where: { $0.role == .assistant && !$0.isComplete })
    }

    /// The identifier of the visible live draft message, if present.
    var liveDraftMessageID: UUID? {
        draftMessage?.id
    }

    /// Whether the current session is authenticated.
    var isSignedIn: Bool {
        sessionStore.isSignedIn
    }

    /// The signed-in account identifier used for ownership-sensitive sync behavior.
    var sessionAccountID: String? {
        sessionStore.currentUser?.id
    }

    /// The derived thinking presentation phase for the current live response surface.
    var thinkingPresentationState: ThinkingPresentationState? {
        BackendConversationSupport.thinkingPresentationState(
            currentThinkingText: currentThinkingText,
            currentStreamingText: currentStreamingText,
            isThinking: isThinking,
            activeToolCalls: activeToolCalls
        )
    }

    /// Whether the detached live bubble should remain visible without an attached draft message.
    var shouldShowDetachedStreamingBubble: Bool {
        guard liveDraftMessageID == nil else {
            return false
        }
        if isConversationRunActive || isThinking {
            return true
        }
        if !currentStreamingText.isEmpty || !currentThinkingText.isEmpty {
            return true
        }
        if !activeToolCalls.isEmpty || !liveCitations.isEmpty || !liveFilePathAnnotations.isEmpty {
            return true
        }
        return false
    }

    /// A derived convenience toggle that maps the service tier onto the flex mode switch.
    var flexModeEnabled: Bool {
        get { serviceTier == .flex }
        set {
            serviceTier = newValue ? .flex : .standard
            persistVisibleConfiguration()
        }
    }
}

@MainActor
extension BackendChatController: BackendConversationDisplayState {
    package var isConversationRunActive: Bool {
        isStreaming
    }
}

@MainActor
extension BackendAgentController: BackendConversationDisplayState {
    package var isConversationRunActive: Bool {
        isRunning
    }
}
