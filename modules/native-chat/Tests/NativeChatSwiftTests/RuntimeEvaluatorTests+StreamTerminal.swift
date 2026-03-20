import ChatRuntimeWorkflows
import Foundation
import Testing

/// Comprehensive edge-case tests for ``StreamTerminalEvaluator``.
///
/// Each test targets a specific branch or edge combination in the
/// prioritized decision tree: completed → recover → retryConnection →
/// finalizePartial → removeEmptyMessage.
struct StreamTerminalEvaluatorEdgeCaseTests {

    // MARK: - Branch 1: Completed

    @Test func completedTakesPrecedenceOverRecoveryID() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: true,
                connectionLost: false,
                pendingRecoveryResponseID: "resp_pending",
                stateResponseID: "resp_state",
                pendingError: "should be ignored",
                hasBufferContent: true,
                lastSequenceNumber: 42,
                usesBackgroundMode: true,
                canRetryConnection: true
            )
        )

        #expect(action == .completed)
    }

    @Test func completedTakesPrecedenceOverConnectionLoss() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: true,
                connectionLost: true,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: false,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: true
            )
        )

        #expect(action == .completed)
    }

    // MARK: - Branch 2: Recover

    @Test func recoverUsesPendingRecoveryIDOverStateID() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: false,
                pendingRecoveryResponseID: "resp_pending",
                stateResponseID: "resp_state",
                pendingError: nil,
                hasBufferContent: false,
                lastSequenceNumber: 5,
                usesBackgroundMode: false,
                canRetryConnection: false
            )
        )

        #expect(
            action == .recover(
                responseID: "resp_pending",
                lastSequenceNumber: 5,
                usesBackgroundMode: false
            )
        )
    }

    @Test func recoverFallsBackToStateIDWhenPendingIsNil() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: false,
                pendingRecoveryResponseID: nil,
                stateResponseID: "resp_state_only",
                pendingError: nil,
                hasBufferContent: false,
                lastSequenceNumber: nil,
                usesBackgroundMode: true,
                canRetryConnection: false
            )
        )

        #expect(
            action == .recover(
                responseID: "resp_state_only",
                lastSequenceNumber: nil,
                usesBackgroundMode: true
            )
        )
    }

    @Test func recoverPassesNilSequenceNumber() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: true,
                pendingRecoveryResponseID: "resp_123",
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: true,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: true
            )
        )

        #expect(
            action == .recover(
                responseID: "resp_123",
                lastSequenceNumber: nil,
                usesBackgroundMode: false
            )
        )
    }

    @Test func recoverTakesPrecedenceOverRetryConnection() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: true,
                pendingRecoveryResponseID: "resp_abc",
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: false,
                lastSequenceNumber: 7,
                usesBackgroundMode: true,
                canRetryConnection: true
            )
        )

        #expect(
            action == .recover(
                responseID: "resp_abc",
                lastSequenceNumber: 7,
                usesBackgroundMode: true
            )
        )
    }

    // MARK: - Branch 3: Retry Connection

    @Test func retryConnectionRequiresBothConnectionLostAndCanRetry() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: true,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: false,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: true
            )
        )

        #expect(action == .retryConnection)
    }

    @Test func connectionLostWithoutCanRetrySkipsToPartialOrRemove() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: true,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: true,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: false
            )
        )

        #expect(action == .finalizePartial)
    }

    @Test func canRetryWithoutConnectionLostSkipsToPartialOrRemove() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: false,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: true,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: true
            )
        )

        #expect(action == .finalizePartial)
    }

    // MARK: - Branch 4: Finalize Partial

    @Test func finalizePartialWhenBufferHasContent() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: false,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: "some error",
                hasBufferContent: true,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: false
            )
        )

        #expect(action == .finalizePartial)
    }

    // MARK: - Branch 5: Remove Empty Message

    @Test func removeEmptyMessageWithPendingError() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: false,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: "Rate limit exceeded",
                hasBufferContent: false,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: false
            )
        )

        #expect(action == .removeEmptyMessage(errorMessage: "Rate limit exceeded"))
    }

    @Test func removeEmptyMessageWithConnectionLostFallback() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: true,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: false,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: false
            )
        )

        #expect(
            action == .removeEmptyMessage(
                errorMessage: "Connection lost. Please check your network and try again."
            )
        )
    }

    @Test func removeEmptyMessageWithNilErrorWhenNotConnectionLost() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: false,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: nil,
                hasBufferContent: false,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: false
            )
        )

        #expect(action == .removeEmptyMessage(errorMessage: nil))
    }

    @Test func pendingErrorTakesPrecedenceOverConnectionLostFallback() {
        let action = StreamTerminalEvaluator.evaluate(
            StreamTerminalOutcome(
                didComplete: false,
                connectionLost: true,
                pendingRecoveryResponseID: nil,
                stateResponseID: nil,
                pendingError: "Server error 500",
                hasBufferContent: false,
                lastSequenceNumber: nil,
                usesBackgroundMode: false,
                canRetryConnection: false
            )
        )

        #expect(action == .removeEmptyMessage(errorMessage: "Server error 500"))
    }
}
