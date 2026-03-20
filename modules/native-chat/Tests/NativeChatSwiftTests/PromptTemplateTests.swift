import ChatDomain
import Foundation
import Testing

/// Tests for ``PromptTemplateDescriptor`` and ``BuiltInPromptTemplates``.
struct PromptTemplateTests {

    // MARK: - Descriptor

    @Test func descriptorHasStableIdentity() {
        let id = UUID()
        let template = PromptTemplateDescriptor(id: id, name: "Test", systemPrompt: "prompt")
        #expect(template.id == id)
    }

    @Test func descriptorEquality() {
        let id = UUID()
        let a = PromptTemplateDescriptor(id: id, name: "A", systemPrompt: "p1")
        let b = PromptTemplateDescriptor(id: id, name: "A", systemPrompt: "p1")
        #expect(a == b)
    }

    @Test func descriptorInequality() {
        let a = PromptTemplateDescriptor(name: "A", systemPrompt: "p1")
        let b = PromptTemplateDescriptor(name: "B", systemPrompt: "p2")
        #expect(a != b)
    }

    @Test func defaultIsNotBuiltIn() {
        let template = PromptTemplateDescriptor(name: "Custom", systemPrompt: "test")
        #expect(template.isBuiltIn == false)
    }

    // MARK: - Built-In Templates

    @Test func builtInTemplateCount() {
        #expect(BuiltInPromptTemplates.all.count == 3)
    }

    @Test func translatorIsBuiltIn() {
        #expect(BuiltInPromptTemplates.translator.isBuiltIn == true)
        #expect(BuiltInPromptTemplates.translator.name == "Translator")
        #expect(!BuiltInPromptTemplates.translator.systemPrompt.isEmpty)
    }

    @Test func codeReviewerIsBuiltIn() {
        #expect(BuiltInPromptTemplates.codeReviewer.isBuiltIn == true)
        #expect(BuiltInPromptTemplates.codeReviewer.name == "Code Reviewer")
        #expect(!BuiltInPromptTemplates.codeReviewer.systemPrompt.isEmpty)
    }

    @Test func writingAssistantIsBuiltIn() {
        #expect(BuiltInPromptTemplates.writingAssistant.isBuiltIn == true)
        #expect(BuiltInPromptTemplates.writingAssistant.name == "Writing Assistant")
        #expect(!BuiltInPromptTemplates.writingAssistant.systemPrompt.isEmpty)
    }

    @Test func allBuiltInsAreMarkedBuiltIn() {
        for template in BuiltInPromptTemplates.all {
            #expect(template.isBuiltIn == true)
        }
    }

    @Test func allBuiltInsHaveUniqueNames() {
        let names = BuiltInPromptTemplates.all.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func allBuiltInsHaveNonEmptyPrompts() {
        for template in BuiltInPromptTemplates.all {
            #expect(!template.systemPrompt.isEmpty)
        }
    }
}
