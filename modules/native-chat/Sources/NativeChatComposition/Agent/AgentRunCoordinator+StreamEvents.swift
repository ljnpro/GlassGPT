import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport

extension AgentRunCoordinator {
    func applyVisibleStreamEvent(
        _ event: StreamEvent,
        execution: AgentExecutionState,
        conversation: Conversation,
        draft: Message
    ) throws {
        try AgentVisibleSynthesisEventApplier.apply(
            event,
            execution: execution,
            conversation: conversation,
            draft: draft,
            coordinator: self
        )
        syncVisibleStateIfNeeded(execution, in: conversation)
    }
}
