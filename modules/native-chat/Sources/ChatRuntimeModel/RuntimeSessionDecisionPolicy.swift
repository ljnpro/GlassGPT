import Foundation

public enum RuntimeRecoveryResumeMode: Equatable, Sendable {
    case stream(lastSequenceNumber: Int)
    case poll
}

public struct RuntimePendingBackgroundCancellation: Equatable, Sendable {
    public let responseId: String
    public let messageId: UUID

    public init(responseId: String, messageId: UUID) {
        self.responseId = responseId
        self.messageId = messageId
    }
}

public enum RuntimeSessionDecisionPolicy {
    public static func recoveryResumeMode(
        preferStreamingResume: Bool,
        usedBackgroundMode: Bool,
        lastSequenceNumber: Int?
    ) -> RuntimeRecoveryResumeMode {
        guard preferStreamingResume, usedBackgroundMode, let lastSequenceNumber else {
            return .poll
        }

        return .stream(lastSequenceNumber: lastSequenceNumber)
    }

    public static func shouldFallbackToDirectRecoveryStream(
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

    public static func shouldPollAfterRecoveryStream(
        encounteredRecoverableFailure: Bool,
        responseId: String?
    ) -> Bool {
        encounteredRecoverableFailure || responseId != nil
    }

    public static func pendingBackgroundCancellation(
        requestUsesBackgroundMode: Bool,
        responseId: String?,
        messageId: UUID
    ) -> RuntimePendingBackgroundCancellation? {
        guard requestUsesBackgroundMode, let responseId else {
            return nil
        }

        return RuntimePendingBackgroundCancellation(responseId: responseId, messageId: messageId)
    }

    public static func canDetachBackgroundResponse(
        hasVisibleSession: Bool,
        usedBackgroundMode: Bool,
        responseId: String?
    ) -> Bool {
        hasVisibleSession && usedBackgroundMode && responseId != nil
    }
}
