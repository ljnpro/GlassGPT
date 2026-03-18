import ChatPersistenceSwiftData
import ChatPersistenceCore
import Foundation

@MainActor
extension ChatLifecycleCoordinator {
    func generateTitlesForUntitledConversations() async {
        guard !controller.apiKey.isEmpty else { return }

        let untitled: [Conversation]
        do {
            untitled = try controller.conversationRepository.fetchUntitledConversations()
        } catch {
            Loggers.chat.error("[Title] Failed to fetch untitled conversations: \(error.localizedDescription)")
            return
        }

        for conversation in untitled {
            guard conversation.messages.count >= 2 else { continue }

            do {
                let title = try await controller.openAIService.generateTitle(
                    for: titlePreview(for: conversation),
                    apiKey: controller.apiKey
                )
                conversation.title = title
                controller.conversationCoordinator.saveContextIfPossible("generateTitlesForUntitledConversations")

                if conversation.id == controller.currentConversation?.id {
                    controller.currentConversation?.title = title
                }

                #if DEBUG
                Loggers.chat.debug("[Title] Generated title for conversation \(conversation.id): \(title)")
                #endif
            } catch {
                #if DEBUG
                Loggers.chat.debug("[Title] Failed to generate title: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func generateTitleIfNeeded(for conversation: Conversation) async {
        guard !controller.apiKey.isEmpty else { return }
        guard conversation.title == "New Chat", conversation.messages.count >= 2 else { return }

        do {
            let title = try await controller.openAIService.generateTitle(
                for: titlePreview(for: conversation),
                apiKey: controller.apiKey
            )
            conversation.title = title
            controller.conversationCoordinator.saveContextIfPossible("generateTitleIfNeeded")
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Title] Failed to generate title: \(error.localizedDescription)")
            #endif
        }
    }

    func generateTitle() async {
        guard let conversation = controller.currentConversation else { return }

        do {
            let title = try await controller.openAIService.generateTitle(
                for: titlePreview(for: conversation, fallbackMessages: controller.messages),
                apiKey: controller.apiKey
            )
            conversation.title = title
            controller.conversationCoordinator.saveContextIfPossible("generateTitle")
        } catch {
            #if DEBUG
            Loggers.chat.debug("[Title] Failed to generate title: \(error.localizedDescription)")
            #endif
        }
    }

    private func titlePreview(for conversation: Conversation, fallbackMessages: [Message]? = nil) -> String {
        let sourceMessages = fallbackMessages ?? conversation.messages
        return sourceMessages
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(4)
            .map { "\($0.roleRawValue): \($0.content.prefix(200))" }
            .joined(separator: "\n")
    }
}
