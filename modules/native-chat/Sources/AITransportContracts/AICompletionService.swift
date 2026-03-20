import ChatDomain
import Foundation

/// Provider-agnostic protocol for AI completion services.
///
/// This protocol defines the interface that any AI provider (OpenAI, Claude, Gemini,
/// Ollama, etc.) must implement to be used as a chat backend. The composition layer
/// depends on this protocol rather than on a specific provider's implementation.
@MainActor
public protocol AICompletionService: Sendable {
    /// Streams a chat completion for the given messages.
    /// - Parameters:
    ///   - apiKey: The API credential.
    ///   - messages: The conversation messages to send.
    ///   - model: The model to use.
    ///   - reasoningEffort: The reasoning effort level.
    ///   - backgroundModeEnabled: Whether background mode is active.
    ///   - serviceTier: The service tier to use.
    ///   - vectorStoreIds: Optional vector store identifiers for file search.
    ///   - systemPrompt: An optional system prompt to prepend.
    /// - Returns: An async stream of provider-agnostic stream events.
    func streamChat(
        apiKey: String,
        messages: [ChatRequestMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String],
        systemPrompt: String?
    ) -> AsyncStream<AIStreamEvent>

    /// Streams a recovery session to resume an interrupted response.
    /// - Parameters:
    ///   - responseId: The response identifier to resume.
    ///   - startingAfter: The last received sequence number, if any.
    ///   - apiKey: The API credential.
    ///   - useDirectBaseURL: Whether to bypass gateway routing.
    /// - Returns: An async stream of provider-agnostic stream events.
    func streamRecovery(
        responseId: String,
        startingAfter: Int?,
        apiKey: String,
        useDirectBaseURL: Bool
    ) -> AsyncStream<AIStreamEvent>

    /// Uploads a file for use in conversation.
    /// - Parameters:
    ///   - data: The file data.
    ///   - filename: The filename.
    ///   - apiKey: The API credential.
    /// - Returns: The provider-assigned file identifier.
    func uploadFile(
        data: Data,
        filename: String,
        apiKey: String
    ) async throws(AIServiceError) -> String

    /// Fetches the current state of a response.
    /// - Parameters:
    ///   - responseId: The response identifier to fetch.
    ///   - apiKey: The API credential.
    /// - Returns: A provider-agnostic fetch result.
    func fetchResponse(
        responseId: String,
        apiKey: String
    ) async throws(AIServiceError) -> AIResponseFetchResult

    /// Cancels any active streaming operation.
    func cancelStream()

    /// Generates a conversation title from the given messages.
    /// - Parameters:
    ///   - messages: The conversation messages.
    ///   - apiKey: The API credential.
    /// - Returns: A generated title string.
    func generateTitle(
        messages: [ChatRequestMessage],
        apiKey: String
    ) async throws(AIServiceError) -> String

    /// Cancels a background response that is still in progress.
    /// - Parameters:
    ///   - responseId: The response identifier to cancel.
    ///   - apiKey: The API credential.
    func cancelBackgroundResponse(
        responseId: String,
        apiKey: String
    ) async throws(AIServiceError)

    /// Transcribes audio data to text using a speech-to-text model.
    /// - Parameters:
    ///   - audioData: The audio data to transcribe.
    ///   - apiKey: The API credential.
    /// - Returns: The transcribed text.
    func transcribe(
        audioData: Data,
        apiKey: String
    ) async throws(AIServiceError) -> String

    /// Synthesizes speech from text using a text-to-speech model.
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voice: An optional voice identifier.
    ///   - apiKey: The API credential.
    /// - Returns: The synthesized audio data.
    func synthesizeSpeech(
        text: String,
        voice: String?,
        apiKey: String
    ) async throws(AIServiceError) -> Data

    /// Generates an image from a text prompt.
    /// - Parameters:
    ///   - prompt: The image description.
    ///   - apiKey: The API credential.
    /// - Returns: The generated image data.
    func generateImage(
        prompt: String,
        apiKey: String
    ) async throws(AIServiceError) -> Data
}
