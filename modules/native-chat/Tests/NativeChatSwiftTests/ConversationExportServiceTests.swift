import ChatApplication
import ChatDomain
import Foundation
import Testing

/// Tests for ``ConversationExportService``.
struct ConversationExportServiceTests {

    // MARK: - Markdown Export

    @Test func markdownExportContainsTitle() {
        let data = ConversationExportService.exportAsMarkdown(
            title: "Test Chat",
            messages: []
        )
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("# Test Chat"))
    }

    @Test func markdownExportRendersUserMessage() {
        let messages = [
            ExportableMessage(role: .user, content: "Hello world")
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("Hello world"))
    }

    @Test func markdownExportRendersAssistantMessage() {
        let messages = [
            ExportableMessage(role: .assistant, content: "Hi there!")
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("Hi there!"))
    }

    @Test func markdownExportIncludesTimestamp() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let messages = [
            ExportableMessage(role: .user, content: "test", createdAt: date)
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        // Should contain a formatted date somewhere
        #expect(markdown.contains("2023") || markdown.contains("Nov"))
    }

    @Test func markdownExportSeparatesMessagesWithDivider() {
        let messages = [
            ExportableMessage(role: .user, content: "Hello"),
            ExportableMessage(role: .assistant, content: "World"),
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("---"))
    }

    @Test func markdownExportHandlesEmptyMessages() {
        let data = ConversationExportService.exportAsMarkdown(title: "Empty", messages: [])
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("# Empty"))
        #expect(!markdown.contains("###"))
    }

    @Test func markdownExportHandlesSystemRole() {
        let messages = [
            ExportableMessage(role: .system, content: "You are helpful")
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("You are helpful"))
    }

    // MARK: - Plain Text Export

    @Test func plainTextExportContainsUppercasedTitle() {
        let data = ConversationExportService.exportAsPlainText(
            title: "My Chat",
            messages: []
        )
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("MY CHAT"))
    }

    @Test func plainTextExportRendersMessages() {
        let messages = [
            ExportableMessage(role: .user, content: "Question"),
            ExportableMessage(role: .assistant, content: "Answer"),
        ]
        let data = ConversationExportService.exportAsPlainText(title: "Chat", messages: messages)
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("Question"))
        #expect(text.contains("Answer"))
    }

    @Test func plainTextExportHandlesEmptyMessages() {
        let data = ConversationExportService.exportAsPlainText(title: "Empty", messages: [])
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("EMPTY"))
    }
}
