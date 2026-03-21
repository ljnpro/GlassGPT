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

    @Test func `completed takes precedence over recovery ID`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(
                didComplete: true,
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

    @Test func `completed takes precedence over connection loss`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(
                didComplete: true,
                connectionLost: true,
                canRetryConnection: true
            )
        )

        #expect(action == .completed)
    }

    // MARK: - Branch 2: Recover

    @Test func `recover uses pending recovery ID over state ID`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(
                pendingRecoveryResponseID: "resp_pending",
                stateResponseID: "resp_state",
                lastSequenceNumber: 5
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

    @Test func `recover falls back to state ID when pending is nil`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(
                stateResponseID: "resp_state_only",
                usesBackgroundMode: true
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

    @Test func `recover passes nil sequence number`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(
                connectionLost: true,
                pendingRecoveryResponseID: "resp_123",
                hasBufferContent: true,
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

    @Test func `recover takes precedence over retry connection`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(
                connectionLost: true,
                pendingRecoveryResponseID: "resp_abc",
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

    @Test func `retry connection requires both connection lost and can retry`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(connectionLost: true, canRetryConnection: true)
        )

        #expect(action == .retryConnection)
    }

    @Test func `connection lost without can retry skips to partial or remove`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(connectionLost: true, hasBufferContent: true)
        )

        #expect(action == .finalizePartial)
    }

    @Test func `can retry without connection lost skips to partial or remove`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(hasBufferContent: true, canRetryConnection: true)
        )

        #expect(action == .finalizePartial)
    }

    // MARK: - Branch 4: Finalize Partial

    @Test func `finalize partial when buffer has content`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(pendingError: "some error", hasBufferContent: true)
        )

        #expect(action == .finalizePartial)
    }

    // MARK: - Branch 5: Remove Empty Message

    @Test func `remove empty message with pending error`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(pendingError: "Rate limit exceeded")
        )

        #expect(action == .removeEmptyMessage(errorMessage: "Rate limit exceeded"))
    }

    @Test func `remove empty message with connection lost fallback`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(connectionLost: true)
        )

        #expect(
            action == .removeEmptyMessage(
                errorMessage: "Connection lost. Please check your network and try again."
            )
        )
    }

    @Test func `remove empty message with nil error when not connection lost`() {
        let action = StreamTerminalEvaluator.evaluate(makeStreamTerminalOutcome())

        #expect(action == .removeEmptyMessage(errorMessage: nil))
    }

    @Test func `pending error takes precedence over connection lost fallback`() {
        let action = StreamTerminalEvaluator.evaluate(
            makeStreamTerminalOutcome(
                connectionLost: true,
                pendingError: "Server error 500"
            )
        )

        #expect(action == .removeEmptyMessage(errorMessage: "Server error 500"))
    }
}

private func makeStreamTerminalOutcome(
    didComplete: Bool = false,
    connectionLost: Bool = false,
    pendingRecoveryResponseID: String? = nil,
    stateResponseID: String? = nil,
    pendingError: String? = nil,
    hasBufferContent: Bool = false,
    lastSequenceNumber: Int? = nil,
    usesBackgroundMode: Bool = false,
    canRetryConnection: Bool = false
) -> StreamTerminalOutcome {
    StreamTerminalOutcome(
        didComplete: didComplete,
        connectionLost: connectionLost,
        pendingRecoveryResponseID: pendingRecoveryResponseID,
        stateResponseID: stateResponseID,
        pendingError: pendingError,
        hasBufferContent: hasBufferContent,
        lastSequenceNumber: lastSequenceNumber,
        usesBackgroundMode: usesBackgroundMode,
        canRetryConnection: canRetryConnection
    )
}
