import Foundation

public enum RecoveryPhase: Equatable, Sendable {
    case idle
    case checkingStatus
    case streamResuming
    case pollingTerminal
}

public enum ChatRuntimeEnginePhase: Equatable, Sendable {
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

public struct ChatRuntimeState: Equatable, Sendable {
    public var phase: ChatRuntimeEnginePhase
    public var recoveryPhase: RecoveryPhase
    public var responseId: String?
    public var lastSequenceNumber: Int?
    public var activeStreamID: UUID
    public var backgroundResumable: Bool
    public var isThinking: Bool

    public init(
        phase: ChatRuntimeEnginePhase = .idle,
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

    public var isStreaming: Bool {
        switch phase {
        case .streaming, .recoveringStream:
            return true
        default:
            return false
        }
    }

    public var isRecovering: Bool {
        recoveryPhase != .idle
    }
}
