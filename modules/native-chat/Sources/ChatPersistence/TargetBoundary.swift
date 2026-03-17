public enum ChatPersistenceBoundary {
    public struct Scope<PersistenceContext, ConversationRepository, DraftRepository, MessagePersistence> {
        public let modelContext: PersistenceContext
        public let conversationRepository: ConversationRepository
        public let draftRepository: DraftRepository
        public let messagePersistence: MessagePersistence

        public init(
            modelContext: PersistenceContext,
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
