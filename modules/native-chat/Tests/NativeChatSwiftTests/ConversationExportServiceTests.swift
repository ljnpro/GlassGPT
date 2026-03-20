import ChatApplication
import ChatDomain
import Foundation
import Testing

/// Tests for ``ConversationExportService``.
struct ConversationExportServiceTests {
    // MARK: - Markdown Export

    @Test func `markdown export contains title`() {
        let data = ConversationExportService.exportAsMarkdown(
            title: "Test Chat",
            messages: []
        )
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("# Test Chat"))
    }

    @Test func `markdown export renders user message`() {
        let messages = [
            ExportableMessage(role: .user, content: "Hello world")
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("Hello world"))
    }

    @Test func `markdown export renders assistant message`() {
        let messages = [
            ExportableMessage(role: .assistant, content: "Hi there!")
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("Hi there!"))
    }

    @Test func `markdown export includes timestamp`() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let messages = [
            ExportableMessage(role: .user, content: "test", createdAt: date)
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        // Should contain a formatted date somewhere
        #expect(markdown.contains("2023") || markdown.contains("Nov"))
    }

    @Test func `markdown export separates messages with divider`() {
        let messages = [
            ExportableMessage(role: .user, content: "Hello"),
            ExportableMessage(role: .assistant, content: "World")
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("---"))
    }

    @Test func `markdown export handles empty messages`() {
        let data = ConversationExportService.exportAsMarkdown(title: "Empty", messages: [])
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("# Empty"))
        #expect(!markdown.contains("###"))
    }

    @Test func `markdown export handles system role`() {
        let messages = [
            ExportableMessage(role: .system, content: "You are helpful")
        ]
        let data = ConversationExportService.exportAsMarkdown(title: "Chat", messages: messages)
        let markdown = String(data: data, encoding: .utf8) ?? ""
        #expect(markdown.contains("You are helpful"))
    }

    // MARK: - Plain Text Export

    @Test func `plain text export contains uppercased title`() {
        let data = ConversationExportService.exportAsPlainText(
            title: "My Chat",
            messages: []
        )
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("MY CHAT"))
    }

    @Test func `plain text export renders messages`() {
        let messages = [
            ExportableMessage(role: .user, content: "Question"),
            ExportableMessage(role: .assistant, content: "Answer")
        ]
        let data = ConversationExportService.exportAsPlainText(title: "Chat", messages: messages)
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("Question"))
        #expect(text.contains("Answer"))
    }

    @Test func `plain text export handles empty messages`() {
        let data = ConversationExportService.exportAsPlainText(title: "Empty", messages: [])
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("EMPTY"))
    }
}
