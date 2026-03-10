import SwiftUI
import SwiftData

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - State

    var messages: [Message] = []
    var currentStreamingText: String = ""
    var currentThinkingText: String = ""
    var isStreaming: Bool = false
    var inputText: String = ""
    var selectedModel: ModelType = .gpt5_4
    var reasoningEffort: ReasoningEffort = .high
    var currentConversation: Conversation?
    var errorMessage: String?
    var showModelSelector: Bool = false
    var selectedImageData: Data?

    // MARK: - Dependencies

    private let openAIService = OpenAIService()
    private let keychainService = KeychainService()
    private var modelContext: ModelContext

    // Stream invalidation token
    private var activeStreamID = UUID()

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Load defaults
        if let savedModel = UserDefaults.standard.string(forKey: "defaultModel"),
           let model = ModelType(rawValue: savedModel) {
            selectedModel = model
        }
        if let savedEffort = UserDefaults.standard.string(forKey: "defaultEffort"),
           let effort = ReasoningEffort(rawValue: savedEffort) {
            reasoningEffort = effort
        }
    }

    // MARK: - API Key

    var apiKey: String {
        keychainService.loadAPIKey() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    // MARK: - Send Message

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "Please add your OpenAI API key in Settings."
            return
        }

        // Create user message
        let userMessage = Message(
            role: .user,
            content: text,
            imageData: selectedImageData
        )

        // Create or update conversation
        if currentConversation == nil {
            let conversation = Conversation(
                model: selectedModel.rawValue,
                reasoningEffort: reasoningEffort.rawValue
            )
            modelContext.insert(conversation)
            currentConversation = conversation
        }

        userMessage.conversation = currentConversation
        currentConversation?.messages.append(userMessage)
        currentConversation?.model = selectedModel.rawValue
        currentConversation?.reasoningEffort = reasoningEffort.rawValue
        currentConversation?.updatedAt = .now
        messages.append(userMessage)

        // Save user message immediately (persist before network call)
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save your message."
            return
        }

        // Clear input
        inputText = ""
        selectedImageData = nil
        errorMessage = nil

        // Start streaming
        isStreaming = true
        currentStreamingText = ""
        currentThinkingText = ""

        HapticService.shared.impact(.light)

        // Snapshot messages as Sendable DTOs (no SwiftData objects cross concurrency boundary)
        let requestAPIKey = apiKey
        let requestModel = selectedModel
        let requestEffort = reasoningEffort
        let requestMessages = messages.map {
            APIMessage(role: $0.role, content: $0.content, imageData: $0.imageData)
        }

        let streamID = UUID()
        activeStreamID = streamID

        Task {
            let stream = openAIService.streamChat(
                apiKey: requestAPIKey,
                messages: requestMessages,
                model: requestModel,
                reasoningEffort: requestEffort
            )

            for await event in stream {
                // Invalidate if a new stream has started
                guard activeStreamID == streamID else { break }

                switch event {
                case .textDelta(let delta):
                    currentStreamingText += delta

                case .thinkingDelta(let delta):
                    currentThinkingText += delta

                case .completed:
                    await finishStreaming()

                case .error(let error):
                    errorMessage = error.localizedDescription
                    isStreaming = false
                    HapticService.shared.notify(.error)
                }
            }
        }
    }

    // MARK: - Stop Generation

    func stopGeneration(savePartial: Bool = true) {
        activeStreamID = UUID() // Invalidate current stream
        openAIService.cancelStream()
        errorMessage = nil

        if savePartial && !currentStreamingText.isEmpty {
            Task { await finishStreaming() }
        } else {
            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
        }

        HapticService.shared.impact(.medium)
    }

    // MARK: - New Chat

    func startNewChat() {
        if isStreaming {
            stopGeneration(savePartial: false)
        }

        currentConversation = nil
        messages = []
        currentStreamingText = ""
        currentThinkingText = ""
        inputText = ""
        errorMessage = nil
        selectedImageData = nil
        HapticService.shared.selection()
    }

    // MARK: - Load Conversation

    func loadConversation(_ conversation: Conversation) {
        if isStreaming {
            stopGeneration(savePartial: false)
        }

        currentConversation = conversation
        messages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
        selectedModel = ModelType(rawValue: conversation.model) ?? .gpt5_4
        reasoningEffort = ReasoningEffort(rawValue: conversation.reasoningEffort) ?? .high
        currentStreamingText = ""
        currentThinkingText = ""
        errorMessage = nil
    }

    // MARK: - Private

    private func finishStreaming() async {
        guard !currentStreamingText.isEmpty else {
            isStreaming = false
            return
        }

        let assistantMessage = Message(
            role: .assistant,
            content: currentStreamingText,
            thinking: currentThinkingText.isEmpty ? nil : currentThinkingText
        )

        assistantMessage.conversation = currentConversation
        currentConversation?.messages.append(assistantMessage)
        currentConversation?.updatedAt = .now
        messages.append(assistantMessage)

        // Save
        try? modelContext.save()

        // Generate title for new conversations
        if currentConversation?.title == "New Chat" && messages.count >= 2 {
            await generateTitle()
        }

        currentStreamingText = ""
        currentThinkingText = ""
        isStreaming = false

        HapticService.shared.notify(.success)
    }

    private func generateTitle() async {
        guard let conversation = currentConversation else { return }

        let preview = messages.prefix(4).map { msg in
            "\(msg.role.rawValue): \(msg.content.prefix(200))"
        }.joined(separator: "\n")

        do {
            let title = try await openAIService.generateTitle(
                for: preview,
                apiKey: apiKey
            )
            conversation.title = title
            try? modelContext.save()
        } catch {
            // Title generation failure is non-critical
        }
    }
}
