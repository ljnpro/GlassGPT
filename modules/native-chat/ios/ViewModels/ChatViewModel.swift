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
    var isThinking: Bool = false          // True while model is reasoning
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

        // Ensure effort is valid for the loaded model
        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
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
        guard !isStreaming else { return }

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
        isThinking = false
        currentStreamingText = ""
        currentThinkingText = ""

        HapticService.shared.impact(.light)

        // Snapshot messages as Sendable DTOs
        let requestAPIKey = apiKey
        let requestModel = selectedModel
        let requestEffort = reasoningEffort
        let requestMessages = messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .map {
                APIMessage(role: $0.role, content: $0.content, imageData: $0.imageData)
            }

        let streamID = UUID()
        activeStreamID = streamID

        Task { @MainActor in
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
                    // When text starts arriving, thinking phase is over
                    if isThinking {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isThinking = false
                        }
                    }
                    currentStreamingText += delta

                case .thinkingDelta(let delta):
                    currentThinkingText += delta

                case .thinkingStarted:
                    withAnimation(.easeIn(duration: 0.2)) {
                        isThinking = true
                    }

                case .thinkingFinished:
                    withAnimation(.easeOut(duration: 0.2)) {
                        isThinking = false
                    }

                case .completed(let fullText, let fullThinking):
                    // Safety net: use the full text from completed event if we missed deltas
                    if !fullText.isEmpty && fullText.count > currentStreamingText.count {
                        currentStreamingText = fullText
                    }
                    if let thinking = fullThinking, !thinking.isEmpty,
                       thinking.count > currentThinkingText.count {
                        currentThinkingText = thinking
                    }
                    await finishStreaming()

                case .error(let error):
                    // If we have partial output, save it before showing error
                    if !currentStreamingText.isEmpty {
                        await finishStreaming()
                    }
                    errorMessage = error.localizedDescription
                    isStreaming = false
                    isThinking = false
                    HapticService.shared.notify(.error)
                }
            }

            // Stream ended without explicit completed event — save what we have
            if activeStreamID == streamID && isStreaming {
                if !currentStreamingText.isEmpty {
                    await finishStreaming()
                } else {
                    isStreaming = false
                    isThinking = false
                }
            }
        }
    }

    // MARK: - Stop Generation

    func stopGeneration(savePartial: Bool = true) {
        activeStreamID = UUID()
        openAIService.cancelStream()
        errorMessage = nil

        if savePartial && !currentStreamingText.isEmpty {
            Task { @MainActor in await finishStreaming() }
        } else {
            currentStreamingText = ""
            currentThinkingText = ""
            isStreaming = false
            isThinking = false
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
        isThinking = false
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

        // Validate effort for loaded model
        if !selectedModel.availableEfforts.contains(reasoningEffort) {
            reasoningEffort = selectedModel.defaultEffort
        }

        currentStreamingText = ""
        currentThinkingText = ""
        errorMessage = nil
        isThinking = false
    }

    // MARK: - Private

    private func finishStreaming() async {
        guard !currentStreamingText.isEmpty else {
            isStreaming = false
            isThinking = false
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
        isThinking = false

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
