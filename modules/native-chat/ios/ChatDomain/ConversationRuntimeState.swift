import Foundation

enum ConversationRuntimePhase: Equatable {
    case idle
    case submitting
    case streaming
    case recoveringStatus
    case recoveringStream
    case recoveringPoll
    case finalizing
    case completed
    case failed
}

struct ConversationRuntimeState: Equatable {
    var phase: ConversationRuntimePhase
    var recoveryPhase: RecoveryPhase
    var responseId: String?
    var lastSequenceNumber: Int?
    var activeStreamID: UUID
    var backgroundResumable: Bool
    var isThinking: Bool

    init(
        phase: ConversationRuntimePhase = .idle,
        recoveryPhase: RecoveryPhase = .idle,
        responseId: String? = nil,
        lastSequenceNumber: Int? = nil,
        activeStreamID: UUID = UUID(),
        backgroundResumable: Bool = false,
        isThinking: Bool = false
    ) {
        self.phase = phase
        self.recoveryPhase = recoveryPhase
        self.responseId = responseId
        self.lastSequenceNumber = lastSequenceNumber
        self.activeStreamID = activeStreamID
        self.backgroundResumable = backgroundResumable
        self.isThinking = isThinking
    }

    var isStreaming: Bool {
        switch phase {
        case .streaming, .recoveringStream:
            return true
        default:
            return false
        }
    }

    var isRecovering: Bool {
        recoveryPhase != .idle
    }
}
