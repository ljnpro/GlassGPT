import ChatRuntimeModel
import Foundation
import OpenAITransport

/// Maps transport-level recovery observations onto runtime-owned actions.
public enum ReplyRecoveryPlanner {
    /// Normalizes a fetched response result into a runtime-owned recovery action.
    /// - Parameters:
    ///   - result: The transport fetch result.
    ///   - preferStreamingResume: Whether streaming resume is preferred.
    ///   - usedBackgroundMode: Whether the original request used background mode.
    ///   - lastSequenceNumber: The last received event sequence number, if any.
    /// - Returns: The next recovery action.
    public static func fetchAction(
        for result: OpenAIResponseFetchResult,
        preferStreamingResume: Bool,
        usedBackgroundMode: Bool,
        lastSequenceNumber: Int?
    ) -> RuntimeRecoveryFetchAction {
        RuntimeSessionDecisionPolicy.recoveryFetchAction(
            status: runtimeStatus(for: result.status),
            preferStreamingResume: preferStreamingResume,
            usedBackgroundMode: usedBackgroundMode,
            lastSequenceNumber: lastSequenceNumber,
            errorMessage: result.errorMessage
        )
    }

    /// Determines the next recovery step when a recovery stream exits without a terminal event.
    /// - Parameters:
    ///   - cloudflareGatewayEnabled: Whether the gateway is enabled.
    ///   - useDirectEndpoint: Whether the direct endpoint is already active.
    ///   - gatewayResumeTimedOut: Whether the gateway attempt timed out.
    ///   - receivedAnyRecoveryEvent: Whether any recovery event arrived.
    ///   - encounteredRecoverableFailure: Whether a recoverable failure occurred.
    ///   - responseId: The response identifier tracked by runtime state, if any.
    /// - Returns: The next runtime-owned recovery step.
    public static func streamNextStep(
        cloudflareGatewayEnabled: Bool,
        useDirectEndpoint: Bool,
        gatewayResumeTimedOut: Bool,
        receivedAnyRecoveryEvent: Bool,
        encounteredRecoverableFailure: Bool,
        responseId: String?
    ) -> RuntimeRecoveryStreamNextStep {
        RuntimeSessionDecisionPolicy.recoveryStreamNextStep(
            cloudflareGatewayEnabled: cloudflareGatewayEnabled,
            useDirectEndpoint: useDirectEndpoint,
            gatewayResumeTimedOut: gatewayResumeTimedOut,
            receivedAnyRecoveryEvent: receivedAnyRecoveryEvent,
            encounteredRecoverableFailure: encounteredRecoverableFailure,
            responseId: responseId
        )
    }

    private static func runtimeStatus(for status: OpenAIResponseFetchResult.Status) -> RuntimeRecoveryStatus {
        switch status {
        case .queued:
            .queued
        case .inProgress:
            .inProgress
        case .completed:
            .completed
        case .incomplete:
            .incomplete
        case .failed, .unknown:
            .failed
        }
    }
}
