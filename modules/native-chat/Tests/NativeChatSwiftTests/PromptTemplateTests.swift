import ChatDomain
import Foundation
import Testing

/// Tests for ``PromptTemplateDescriptor`` and ``BuiltInPromptTemplates``.
struct PromptTemplateTests {
    // MARK: - Descriptor

    @Test func `descriptor has stable identity`() {
        let id = UUID()
        let template = PromptTemplateDescriptor(id: id, name: "Test", systemPrompt: "prompt")
        #expect(template.id == id)
    }

    @Test func `descriptor equality`() {
        let id = UUID()
        let a = PromptTemplateDescriptor(id: id, name: "A", systemPrompt: "p1")
        let b = PromptTemplateDescriptor(id: id, name: "A", systemPrompt: "p1")
        #expect(a == b)
    }

    @Test func `descriptor inequality`() {
        let a = PromptTemplateDescriptor(name: "A", systemPrompt: "p1")
        let b = PromptTemplateDescriptor(name: "B", systemPrompt: "p2")
        #expect(a != b)
    }

    @Test func `default is not built in`() {
        let template = PromptTemplateDescriptor(name: "Custom", systemPrompt: "test")
        #expect(template.isBuiltIn == false)
    }

    // MARK: - Built-In Templates

    @Test func `built in template count`() {
        #expect(BuiltInPromptTemplates.all.count == 3)
    }

    @Test func `translator is built in`() {
        #expect(BuiltInPromptTemplates.translator.isBuiltIn == true)
        #expect(BuiltInPromptTemplates.translator.name == "Translator")
        #expect(!BuiltInPromptTemplates.translator.systemPrompt.isEmpty)
    }

    @Test func `code reviewer is built in`() {
        #expect(BuiltInPromptTemplates.codeReviewer.isBuiltIn == true)
        #expect(BuiltInPromptTemplates.codeReviewer.name == "Code Reviewer")
        #expect(!BuiltInPromptTemplates.codeReviewer.systemPrompt.isEmpty)
    }

    @Test func `writing assistant is built in`() {
        #expect(BuiltInPromptTemplates.writingAssistant.isBuiltIn == true)
        #expect(BuiltInPromptTemplates.writingAssistant.name == "Writing Assistant")
        #expect(!BuiltInPromptTemplates.writingAssistant.systemPrompt.isEmpty)
    }

    @Test func `all built ins are marked built in`() {
        for template in BuiltInPromptTemplates.all {
            #expect(template.isBuiltIn == true)
        }
    }

    @Test func `all built ins have unique names`() {
        let names = BuiltInPromptTemplates.all.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func `all built ins have non empty prompts`() {
        for template in BuiltInPromptTemplates.all {
            #expect(!template.systemPrompt.isEmpty)
        }
    }
}
