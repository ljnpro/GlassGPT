import ChatPresentation
import Testing

struct ThinkingPresentationStateTests {
    struct Scenario {
        let hasResponseText: Bool
        let isThinking: Bool
        let isAwaitingResponse: Bool
        let expected: ThinkingPresentationState
    }

    @Test(arguments: [
        Scenario(hasResponseText: false, isThinking: true, isAwaitingResponse: true, expected: .reasoning),
        Scenario(hasResponseText: false, isThinking: false, isAwaitingResponse: true, expected: .waiting),
        Scenario(hasResponseText: true, isThinking: true, isAwaitingResponse: true, expected: .completed),
        Scenario(hasResponseText: false, isThinking: false, isAwaitingResponse: false, expected: .completed)
    ])
    func `thinking presentation state resolves visible phase`(_ scenario: Scenario) {
        #expect(
            ThinkingPresentationState.resolve(
                hasResponseText: scenario.hasResponseText,
                isThinking: scenario.isThinking,
                isAwaitingResponse: scenario.isAwaitingResponse
            ) == scenario.expected
        )
    }
}
