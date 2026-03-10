import SwiftUI
import PhotosUI
import UIKit

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            chatContent
                .safeAreaInset(edge: .bottom) {
                    MessageInputBar(
                        text: $viewModel.inputText,
                        isStreaming: viewModel.isStreaming,
                        selectedImageData: $viewModel.selectedImageData,
                        onSend: { viewModel.sendMessage() },
                        onStop: { viewModel.stopGeneration() },
                        onPickImage: { showPhotoPicker = true }
                    )
                }
                .navigationTitle(viewModel.currentConversation?.title ?? "New Chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.startNewChat()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .buttonStyle(.glass)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        ModelBadge(
                            model: viewModel.selectedModel,
                            effort: viewModel.reasoningEffort,
                            onTap: { viewModel.showModelSelector.toggle() }
                        )
                    }
                }
                .sheet(isPresented: $viewModel.showModelSelector) {
                    ModelSelectorSheet(
                        selectedModel: $viewModel.selectedModel,
                        reasoningEffort: $viewModel.reasoningEffort
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
                .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        // Normalize to JPEG to avoid MIME type issues
                        guard
                            let rawData = try? await newItem?.loadTransferable(type: Data.self),
                            let image = UIImage(data: rawData),
                            let jpegData = image.jpegData(compressionQuality: 0.85)
                        else {
                            return
                        }
                        viewModel.selectedImageData = jpegData
                    }
                }
        }
    }

    // MARK: - Chat Content

    @ViewBuilder
    private var chatContent: some View {
        if viewModel.messages.isEmpty && !viewModel.isStreaming {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming message
                        if viewModel.isStreaming {
                            streamingBubble
                                .id("streaming")
                        }

                        // Error message
                        if let error = viewModel.errorMessage {
                            errorBanner(error)
                        }

                        // Anchor
                        Color.clear.frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollProxy = proxy }
                .onChange(of: viewModel.currentStreamingText) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolEffect(.breathe)

            Text("Start a Conversation")
                .font(.title2.weight(.semibold))

            Text("Type a message below to begin chatting with AI")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !viewModel.hasAPIKey {
                Label("Add your API key in Settings", systemImage: "key.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
        }
        .padding(40)
    }

    // MARK: - Streaming Bubble

    private var streamingBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.currentThinkingText.isEmpty {
                    ThinkingView(text: viewModel.currentThinkingText)
                }

                if !viewModel.currentStreamingText.isEmpty {
                    MarkdownContentView(text: viewModel.currentStreamingText)
                } else if viewModel.currentThinkingText.isEmpty {
                    TypingIndicator()
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            }
            .glassEffect(.regular.interactive, in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)

            Spacer(minLength: 40)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}
