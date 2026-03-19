import Foundation

/// Determines how a recovery session should resume: by streaming or polling.
public enum RuntimeRecoveryResumeMode: Equatable, Sendable {
    /// Resume by streaming from the given sequence number.
    case stream(lastSequenceNumber: Int)
    /// Resume by polling for the completed response.
    case poll
}

/// Represents a pending cancellation request for a background response.
public struct RuntimePendingBackgroundCancellation: Equatable, Sendable {
    /// The API response identifier to cancel.
    public let responseId: String
    /// The message identifier associated with the cancellation.
    public let messageId: UUID

    /// Creates a new pending background cancellation.
    /// - Parameters:
    ///   - responseId: The API response identifier.
    ///   - messageId: The associated message identifier.
    public init(responseId: String, messageId: UUID) {
        self.responseId = responseId
        self.messageId = messageId
    }
}

/// Pure-function policy decisions for runtime session management.
///
/// All methods are stateless and deterministic, making them straightforward to test.
public enum RuntimeSessionDecisionPolicy {
    /// Determines the appropriate resume mode for a recovery attempt.
    /// - Parameters:
    ///   - preferStreamingResume: Whether the caller prefers streaming over polling.
    ///   - usedBackgroundMode: Whether the original request used background mode.
    ///   - lastSequenceNumber: The last received sequence number, if any.
    /// - Returns: The resume mode to use for recovery.
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

    /// Determines whether recovery should fall back to a direct endpoint stream.
    /// - Parameters:
    ///   - cloudflareGatewayEnabled: Whether the Cloudflare gateway is configured.
    ///   - useDirectEndpoint: Whether the direct endpoint is already in use.
    ///   - gatewayResumeTimedOut: Whether the gateway resume attempt timed out.
    ///   - receivedAnyRecoveryEvent: Whether any events were received during recovery.
    /// - Returns: `true` if the runtime should fall back to a direct recovery stream.
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

    /// Determines whether recovery should fall back to polling after a stream attempt.
    /// - Parameters:
    ///   - encounteredRecoverableFailure: Whether a recoverable failure occurred.
    ///   - responseId: The API response identifier, if available.
    /// - Returns: `true` if polling should be attempted after stream recovery.
    public static func shouldPollAfterRecoveryStream(
        encounteredRecoverableFailure: Bool,
        responseId: String?
    ) -> Bool {
        encounteredRecoverableFailure || responseId != nil
    }

    /// Creates a pending cancellation if a background response should be cancelled on user action.
    /// - Parameters:
    ///   - requestUsesBackgroundMode: Whether the request used background mode.
    ///   - responseId: The API response identifier, if available.
    ///   - messageId: The message identifier.
    /// - Returns: A pending cancellation descriptor, or `nil` if cancellation is not applicable.
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

    /// Determines whether a background response can be detached from the active session.
    /// - Parameters:
    ///   - hasVisibleSession: Whether the reply session is currently visible.
    ///   - usedBackgroundMode: Whether background mode was used.
    ///   - responseId: The API response identifier, if available.
    /// - Returns: `true` if the response can be detached for background processing.
    public static func canDetachBackgroundResponse(
        hasVisibleSession: Bool,
        usedBackgroundMode: Bool,
        responseId: String?
    ) -> Bool {
        hasVisibleSession && usedBackgroundMode && responseId != nil
    }
}
