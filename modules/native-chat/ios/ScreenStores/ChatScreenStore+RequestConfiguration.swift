import Foundation

@MainActor
extension ChatScreenStore {
    func sessionRequestConfiguration(for conversation: Conversation?) -> (ModelType, ReasoningEffort, ServiceTier) {
        guard let conversation else {
            let effort = selectedModel.availableEfforts.contains(reasoningEffort) ? reasoningEffort : selectedModel.defaultEffort
            return (selectedModel, effort, serviceTier)
        }

        let model = ModelType(rawValue: conversation.model) ?? .gpt5_4
        let storedEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        let resolvedEffort = model.availableEfforts.contains(storedEffort) ? storedEffort : model.defaultEffort
        let resolvedTier = ServiceTier(rawValue: conversation.serviceTierRawValue) ?? .standard
        return (model, resolvedEffort, resolvedTier)
    }

    func buildRequestMessages(for conversation: Conversation, excludingDraft draftID: UUID) -> [APIMessage] {
        conversation.messages
            .filter { $0.id != draftID && ($0.isComplete || $0.role == .user) }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map {
                APIMessage(
                    role: $0.role,
                    content: $0.content,
                    imageData: $0.imageData,
                    fileAttachments: $0.fileAttachments
                )
            }
    }
}
