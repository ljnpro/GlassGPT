import ChatDomain
import Testing

/// Tests for ``AppIntentDescriptor`` and ``GlassGPTAppIntents``.
struct AppIntentDescriptorTests {
    @Test func `ask GPT intent has valid identifier`() {
        let intent = GlassGPTAppIntents.askGPT
        #expect(intent.identifier == "com.glassgpt.intent.ask")
        #expect(!intent.title.isEmpty)
        #expect(!intent.description.isEmpty)
    }

    @Test func `new chat intent has valid identifier`() {
        let intent = GlassGPTAppIntents.newChat
        #expect(intent.identifier == "com.glassgpt.intent.newchat")
        #expect(!intent.title.isEmpty)
        #expect(!intent.description.isEmpty)
    }

    @Test func `all intents are registered`() {
        #expect(GlassGPTAppIntents.all.count == 2)
    }

    @Test func `all intents have unique identifiers`() {
        let ids = GlassGPTAppIntents.all.map(\.identifier)
        #expect(Set(ids).count == ids.count)
    }

    @Test func `descriptor equality`() {
        let lhs = AppIntentDescriptor(identifier: "test", title: "Test", description: "desc")
        let rhs = AppIntentDescriptor(identifier: "test", title: "Test", description: "desc")
        #expect(lhs == rhs)
    }

    @Test func `descriptor inequality`() {
        let lhs = AppIntentDescriptor(identifier: "a", title: "A", description: "d")
        let rhs = AppIntentDescriptor(identifier: "b", title: "B", description: "d")
        #expect(lhs != rhs)
    }
}
