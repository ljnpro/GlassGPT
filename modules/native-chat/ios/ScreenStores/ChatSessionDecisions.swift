import Foundation

enum ChatRecoveryResumeMode: Equatable {
    case stream(lastSequenceNumber: Int)
    case poll
}

struct PendingBackgroundCancellation: Equatable {
    let responseId: String
    let messageId: UUID
}

enum ChatSessionDecisions {
    static func recoveryResumeMode(
        preferStreamingResume: Bool,
        usedBackgroundMode: Bool,
        lastSequenceNumber: Int?
    ) -> ChatRecoveryResumeMode {
        guard preferStreamingResume, usedBackgroundMode, let lastSequenceNumber else {
            return .poll
        }

        return .stream(lastSequenceNumber: lastSequenceNumber)
    }

    static func shouldFallbackToDirectRecoveryStream(
        cloudflareGatewayEnabled: Bool,
        useDirectEndpoint: Bool,
        gatewayResumeTimedOut: Bool,
        receivedAnyRecoveryEvent: Bool
    ) -> Bool {
        guard cloudflareGatewayEnabled, !useDirectEndpoint else {
            return false
        }

        return gatewayResumeTimedOut || !receivedAnyRecoveryEvent
    }

    static func shouldPollAfterRecoveryStream(
        encounteredRecoverableFailure: Bool,
        responseId: String?
    ) -> Bool {
        encounteredRecoverableFailure || responseId != nil
    }

    static func pendingBackgroundCancellation(
        requestUsesBackgroundMode: Bool,
        responseId: String?,
        messageId: UUID
    ) -> PendingBackgroundCancellation? {
        guard requestUsesBackgroundMode, let responseId else {
            return nil
        }

        return PendingBackgroundCancellation(responseId: responseId, messageId: messageId)
    }

    static func canDetachBackgroundResponse(
        hasVisibleSession: Bool,
        usedBackgroundMode: Bool,
        responseId: String?
    ) -> Bool {
        hasVisibleSession && usedBackgroundMode && responseId != nil
    }
}
