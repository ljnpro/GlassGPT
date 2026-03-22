import Foundation

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

    /// Determines the runtime-owned next step after a detached response fetch.
    /// - Parameters:
    ///   - status: The normalized recovery status.
    ///   - preferStreamingResume: Whether the caller prefers streaming over polling.
    ///   - usedBackgroundMode: Whether the original request used background mode.
    ///   - lastSequenceNumber: The last received sequence number, if any.
    ///   - errorMessage: The terminal error message, if any.
    /// - Returns: The runtime fetch action to execute.
    public static func recoveryFetchAction(
        status: RuntimeRecoveryStatus,
        preferStreamingResume: Bool,
        usedBackgroundMode: Bool,
        lastSequenceNumber: Int?,
        errorMessage: String?
    ) -> RuntimeRecoveryFetchAction {
        // Terminal fetch states stay semantically distinct so incomplete work does not
        // get collapsed into a hard failure. Only queued/in-progress states re-enter
        // the recovery transport loop.
        switch status {
        case .completed:
            .finish(.completed)
        case .incomplete:
            .finish(.incomplete(errorMessage))
        case .failed:
            .finish(.failed(errorMessage))
        case .queued, .inProgress:
            switch recoveryResumeMode(
                preferStreamingResume: preferStreamingResume,
                usedBackgroundMode: usedBackgroundMode,
                lastSequenceNumber: lastSequenceNumber
            ) {
            case let .stream(lastSequenceNumber):
                .startStream(lastSequenceNumber: lastSequenceNumber)
            case .poll:
                .poll
            }
        }
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

    /// Determines the runtime-owned next step after a recovery stream exits.
    /// - Parameters:
    ///   - cloudflareGatewayEnabled: Whether the Cloudflare gateway is configured.
    ///   - useDirectEndpoint: Whether the direct endpoint is already in use.
    ///   - gatewayResumeTimedOut: Whether the gateway resume attempt timed out.
    ///   - receivedAnyRecoveryEvent: Whether any events were received during recovery.
    ///   - encounteredRecoverableFailure: Whether a recoverable failure occurred.
    ///   - responseId: The API response identifier, if available.
    /// - Returns: The next recovery step to execute.
    public static func recoveryStreamNextStep(
        cloudflareGatewayEnabled: Bool,
        useDirectEndpoint: Bool,
        gatewayResumeTimedOut: Bool,
        receivedAnyRecoveryEvent: Bool,
        encounteredRecoverableFailure: Bool,
        responseId: String?
    ) -> RuntimeRecoveryStreamNextStep {
        // Gateway resume fallback wins before polling because a timeout or zero-event
        // recovery stream usually indicates the transport path is unhealthy, not that
        // the response itself has reached a terminal state.
        if shouldFallbackToDirectRecoveryStream(
            cloudflareGatewayEnabled: cloudflareGatewayEnabled,
            useDirectEndpoint: useDirectEndpoint,
            gatewayResumeTimedOut: gatewayResumeTimedOut,
            receivedAnyRecoveryEvent: receivedAnyRecoveryEvent
        ) {
            return .retryDirectStream
        }

        if shouldPollAfterRecoveryStream(
            encounteredRecoverableFailure: encounteredRecoverableFailure,
            responseId: responseId
        ) {
            return .poll
        }

        return .none
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
