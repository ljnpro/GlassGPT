import ChatDomain
import Foundation

/// A single exportable message with role and content.
public struct ExportableMessage: Sendable {
    /// The role of the message author.
    public let role: MessageRole
    /// The text content of the message.
    public let content: String
    /// The timestamp when the message was created.
    public let createdAt: Date?

    /// Creates an exportable message.
    public init(role: MessageRole, content: String, createdAt: Date? = nil) {
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

/// Service for exporting conversations to Markdown or PDF format.
///
/// Renders a list of ``ExportableMessage`` values into a formatted document
/// suitable for sharing or archiving.
public enum ConversationExportService {
    /// Exports messages to Markdown format.
    /// - Parameters:
    ///   - title: The conversation title.
    ///   - messages: The messages to export.
    /// - Returns: The Markdown text as UTF-8 data.
    public static func exportAsMarkdown(
        title: String,
        messages: [ExportableMessage]
    ) -> Data {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        for message in messages {
            let roleLabel = roleHeader(for: message.role)
            if let date = message.createdAt {
                lines.append("### \(roleLabel) — \(formatter.string(from: date))")
            } else {
                lines.append("### \(roleLabel)")
            }
            lines.append("")
            lines.append(message.content)
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        let markdown = lines.joined(separator: "\n")
        return Data(markdown.utf8)
    }

    /// Exports messages to plain-text format suitable for PDF rendering.
    /// - Parameters:
    ///   - title: The conversation title.
    ///   - messages: The messages to export.
    /// - Returns: The formatted plain text as UTF-8 data.
    public static func exportAsPlainText(
        title: String,
        messages: [ExportableMessage]
    ) -> Data {
        var lines: [String] = []
        lines.append(title.uppercased())
        lines.append(String(repeating: "=", count: title.count))
        lines.append("")

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        for message in messages {
            let roleLabel = roleHeader(for: message.role)
            if let date = message.createdAt {
                lines.append("[\(roleLabel)] \(formatter.string(from: date))")
            } else {
                lines.append("[\(roleLabel)]")
            }
            lines.append(message.content)
            lines.append("")
        }

        let text = lines.joined(separator: "\n")
        return Data(text.utf8)
    }

    private static func roleHeader(for role: MessageRole) -> String {
        switch role {
        case .user:
            String(localized: "You")
        case .assistant:
            String(localized: "Assistant")
        case .system:
            String(localized: "System")
        }
    }
}
