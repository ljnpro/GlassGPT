import Foundation

/// A reusable prompt template that provides a system prompt for new conversations.
///
/// Users can create, save, and select templates to quickly configure
/// conversations with custom system instructions.
public struct PromptTemplateDescriptor: Sendable, Equatable, Identifiable {
    /// The unique identifier for this template.
    public let id: UUID
    /// The human-readable name of the template.
    public let name: String
    /// The system prompt text applied when the template is selected.
    public let systemPrompt: String
    /// Whether this is a built-in template (cannot be deleted by the user).
    public let isBuiltIn: Bool

    /// Creates a new prompt template descriptor.
    public init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.isBuiltIn = isBuiltIn
    }
}

/// Built-in starter templates shipped with the app.
public enum BuiltInPromptTemplates {
    /// A translation assistant template.
    public static let translator = PromptTemplateDescriptor(
        name: "Translator",
        systemPrompt: """
        You are a professional translator. Translate the user's text accurately,
        preserving tone and nuance. If no target language is specified, translate
        to English. Provide only the translation without explanations unless asked.
        """,
        isBuiltIn: true
    )

    /// A code review assistant template.
    public static let codeReviewer = PromptTemplateDescriptor(
        name: "Code Reviewer",
        systemPrompt: """
        You are a senior software engineer performing a thorough code review.
        Focus on correctness, performance, security, readability, and
        maintainability. Provide specific, actionable feedback with examples.
        Highlight both issues and well-written code.
        """,
        isBuiltIn: true
    )

    /// A writing assistant template.
    public static let writingAssistant = PromptTemplateDescriptor(
        name: "Writing Assistant",
        systemPrompt: """
        You are a professional writing assistant. Help the user improve their
        writing by focusing on clarity, grammar, tone, and structure. Provide
        suggestions while preserving the author's voice and intent.
        """,
        isBuiltIn: true
    )

    /// All built-in templates.
    public static let all: [PromptTemplateDescriptor] = [
        translator,
        codeReviewer,
        writingAssistant
    ]
}
