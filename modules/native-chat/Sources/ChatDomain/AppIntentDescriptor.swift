import Foundation

/// Describes an App Intent action that can be exposed to Shortcuts and Siri.
///
/// This descriptor lives in the domain layer so that the Xcode app target
/// can register concrete `AppIntent` conformances while keeping the
/// action definition shared across modules.
public struct AppIntentDescriptor: Sendable, Equatable {
    /// The intent identifier used for registration.
    public let identifier: String
    /// The human-readable title shown in the Shortcuts app.
    public let title: String
    /// A brief description of what the intent does.
    public let description: String

    /// Creates a new intent descriptor.
    public init(identifier: String, title: String, description: String) {
        self.identifier = identifier
        self.title = title
        self.description = description
    }
}

/// The set of App Intents that GlassGPT exposes.
public enum GlassGPTAppIntents {
    /// Ask GPT a question via Shortcuts or Siri.
    public static let askGPT = AppIntentDescriptor(
        identifier: "com.glassgpt.intent.ask",
        title: "Ask GPT",
        description: "Send a question to GPT and get a response."
    )

    /// Start a new conversation.
    public static let newChat = AppIntentDescriptor(
        identifier: "com.glassgpt.intent.newchat",
        title: "New Chat",
        description: "Start a new conversation in GlassGPT."
    )

    /// All registered intents.
    public static let all: [AppIntentDescriptor] = [askGPT, newChat]
}
