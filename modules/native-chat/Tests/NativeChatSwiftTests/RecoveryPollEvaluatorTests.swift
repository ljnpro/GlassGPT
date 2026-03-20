import ChatRuntimeWorkflows
import Foundation
import OpenAITransport
import Testing

struct RecoveryPollEvaluatorTests {
    @Test(arguments: [OpenAIResponseFetchResult.Status.queued, .inProgress])
    func `evaluate stops polling when nonterminal result reaches max attempts`(
        status: OpenAIResponseFetchResult.Status
    ) {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                result: makeResult(status: status),
                attempt: 3,
                maxAttempts: 3
            )
        )

        guard case let .terminal(result, errorMessage) = action else {
            Issue.record("Expected terminal action at polling limit")
            return
        }

        #expect(result.status == status)
        #expect(errorMessage == "Recovery polling exceeded maximum attempts.")
    }

    @Test func `evaluate stops polling when transient errors reach max attempts`() {
        let action = RecoveryPollEvaluator.evaluate(
            PollAttemptOutcome(
                error: RecoveryPollEvaluatorTestError.transient,
                attempt: 2,
                maxAttempts: 2
            )
        )

        guard case let .terminal(result, errorMessage) = action else {
            Issue.record("Expected terminal action at polling limit")
            return
        }

        #expect(result.status == .failed)
        #expect(errorMessage == RecoveryPollEvaluatorTestError.transient.localizedDescription)
    }
}

private func makeResult(
    status: OpenAIResponseFetchResult.Status,
    errorMessage: String? = nil
) -> OpenAIResponseFetchResult {
    OpenAIResponseFetchResult(
        status: status,
        text: "",
        thinking: nil,
        annotations: [],
        toolCalls: [],
        filePathAnnotations: [],
        errorMessage: errorMessage
    )
}

private enum RecoveryPollEvaluatorTestError: LocalizedError {
    case transient

    var errorDescription: String? {
        "Temporary failure"
    }
}
