public enum ChatPersistenceBoundary {
    public struct Scope<ModelContext, ConversationRepository, DraftRepository, MessagePersistence> {
        public let modelContext: ModelContext
        public let conversationRepository: ConversationRepository
        public let draftRepository: DraftRepository
        public let messagePersistence: MessagePersistence

        public init(
            modelContext: ModelContext,
            conversationRepository: ConversationRepository,
            draftRepository: DraftRepository,
            messagePersistence: MessagePersistence
        ) {
            self.modelContext = modelContext
            self.conversationRepository = conversationRepository
            self.draftRepository = draftRepository
            self.messagePersistence = messagePersistence
        }
    }
}
