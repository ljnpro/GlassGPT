import ChatDomain
import Testing

/// Tests for ``AppIntentDescriptor`` and ``GlassGPTAppIntents``.
struct AppIntentDescriptorTests {

    @Test func askGPTIntentHasValidIdentifier() {
        let intent = GlassGPTAppIntents.askGPT
        #expect(intent.identifier == "com.glassgpt.intent.ask")
        #expect(!intent.title.isEmpty)
        #expect(!intent.description.isEmpty)
    }

    @Test func newChatIntentHasValidIdentifier() {
        let intent = GlassGPTAppIntents.newChat
        #expect(intent.identifier == "com.glassgpt.intent.newchat")
        #expect(!intent.title.isEmpty)
        #expect(!intent.description.isEmpty)
    }

    @Test func allIntentsAreRegistered() {
        #expect(GlassGPTAppIntents.all.count == 2)
    }

    @Test func allIntentsHaveUniqueIdentifiers() {
        let ids = GlassGPTAppIntents.all.map(\.identifier)
        #expect(Set(ids).count == ids.count)
    }

    @Test func descriptorEquality() {
        let a = AppIntentDescriptor(identifier: "test", title: "Test", description: "desc")
        let b = AppIntentDescriptor(identifier: "test", title: "Test", description: "desc")
        #expect(a == b)
    }

    @Test func descriptorInequality() {
        let a = AppIntentDescriptor(identifier: "a", title: "A", description: "d")
        let b = AppIntentDescriptor(identifier: "b", title: "B", description: "d")
        #expect(a != b)
    }
}
