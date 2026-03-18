import ChatPersistenceSwiftData
import ChatDomain
import ChatPersistenceCore
import Foundation
import NativeChatComposition
import SwiftData
import UIKit

@MainActor
extension UITestScenarioLoader {
    static func clearAllConversations(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Conversation>()
        let conversations: [Conversation]

        do {
            conversations = try modelContext.fetch(descriptor)
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to fetch conversations for reset: \(error.localizedDescription)")
            return
        }

        for conversation in conversations {
            modelContext.delete(conversation)
        }

        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to save reset state: \(error.localizedDescription)")
        }
    }

    static func seedConversationsIfNeeded(
        in modelContext: ModelContext,
        scenario: UITestScenario
    ) -> [Conversation] {
        let conversations: [Conversation]
        switch scenario {
        case .empty, .settings, .settingsGateway, .reinstallSeed, .reinstallVerify, .freshInstall:
            return []
        case .seeded, .streaming, .preview:
            conversations = [
                makeConversation(title: "Release Planning", timeOffset: 0, backgroundModeEnabled: false)
            ]
        case .replySplit:
            return [makeRichMarkdownConversation(in: modelContext)]
        case .history:
            conversations = [
                makeConversation(title: "Release Planning", timeOffset: 0, backgroundModeEnabled: false),
                makeConversation(title: "Archive Audit", timeOffset: -120, backgroundModeEnabled: true),
                makeConversation(title: "Snapshot Review", timeOffset: -240, backgroundModeEnabled: false)
            ]
        }

        for conversation in conversations {
            modelContext.insert(conversation)
            for message in conversation.messages {
                modelContext.insert(message)
            }
        }

        do {
            try modelContext.save()
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to save seeded conversations: \(error.localizedDescription)")
        }

        return conversations
    }

    static func makeConversation(
        title: String,
        timeOffset: TimeInterval,
        backgroundModeEnabled: Bool
    ) -> Conversation {
        let createdAt = Date(timeIntervalSinceNow: timeOffset)
        let updatedAt = Date(timeIntervalSinceNow: timeOffset)
        let conversation = Conversation(
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )

        let userMessage = Message(
            role: .user,
            content: "Can you keep the refactor zero-diff?"
        )
        let assistantMessage = Message(
            role: .assistant,
            content: "Yes. I will preserve the current UX and tighten the internal architecture only.",
            thinking: "Compare the current streaming behavior, preserve background mode semantics, and keep the visual output locked."
        )

        conversation.messages = [userMessage, assistantMessage]
        userMessage.conversation = conversation
        assistantMessage.conversation = conversation

        return conversation
    }

    static func makeRichMarkdownConversation(in modelContext: ModelContext) -> Conversation {
        let conversation = RichAssistantReplyFixture.makeConversation()

        do {
            try RichAssistantReplyFixture.insertConversation(conversation, into: modelContext)
        } catch {
            Loggers.persistence.error("[UITestScenarioLoader] Failed to save rich markdown conversation: \(error.localizedDescription)")
        }

        return conversation
    }

    static func makePreviewImageURL() -> URL? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))

            UIColor.white.setFill()
            context.fill(CGRect(x: 80, y: 120, width: 1040, height: 620))

            let title = "Generated Chart" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            title.draw(at: CGPoint(x: 120, y: 180), withAttributes: attributes)
        }

        guard let data = image.pngData() else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-test-generated-chart.png")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Loggers.files.error("[UITestScenarioLoader] Failed to write preview image: \(error.localizedDescription)")
            return nil
        }
    }
}
