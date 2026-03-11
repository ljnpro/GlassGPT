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
            ZStack {
                chatContent

                // Restoring conversation overlay
                if viewModel.isRestoringConversation {
                    restoringOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isRestoringConversation)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MessageInputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    selectedImageData: $viewModel.selectedImageData,
                    onSend: { viewModel.sendMessage() },
                    onStop: { viewModel.stopGeneration() },
                    onPickImage: { showPhotoPicker = true }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModelBadge(
                        model: viewModel.selectedModel,
                        effort: viewModel.reasoningEffort,
                        onTap: { viewModel.showModelSelector.toggle() }
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Chat", systemImage: "square.and.pencil") {
                        viewModel.startNewChat()
                    }
                    .buttonStyle(.glass)
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $viewModel.showModelSelector) {
                ModelSelectorSheet(
                    selectedModel: $viewModel.selectedModel,
                    reasoningEffort: $viewModel.reasoningEffort
                )
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    do {
                        guard
                            let rawData = try await newItem?.loadTransferable(type: Data.self),
                            let image = UIImage(data: rawData),
                            let jpegData = image.jpegData(compressionQuality: 0.85)
                        else {
                            return
                        }
                        viewModel.selectedImageData = jpegData
                    } catch {
                        print("Failed to load photo: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Chat Content

    @ViewBuilder
    private var chatContent: some View {
        if viewModel.messages.isEmpty && !viewModel.isStreaming && !viewModel.isRestoringConversation {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                onRegenerate: message.role == .assistant ? {
                                    viewModel.regenerateMessage(message)
                                } : nil
                            )
                            .id(message.id)
                        }

                        // Streaming message
                        if viewModel.isStreaming {
                            streamingBubble
                                .id("streaming")
                        }

                        // Recovery indicator
                        if viewModel.isRecovering {
                            recoveryBanner
                                .id("recovery")
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
                    .padding(.bottom, 4)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollProxy = proxy }
                .onChange(of: viewModel.currentStreamingText) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.currentThinkingText) { _, _ in
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

    // MARK: - Restoring Overlay

    private var restoringOverlay: some View {
        VStack(spacing: 12) {
            Spacer()

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Restoring conversation…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .glassEffect(.regular, in: Capsule())

            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolEffect(.breathe)

            Text("Start a Conversation")
                .font(.title2.weight(.semibold))

            if !viewModel.hasAPIKey {
                Label("Add your API key in Settings", systemImage: "key.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Streaming Bubble

    private var streamingBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isThinking {
                    ThinkingIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                if !viewModel.currentThinkingText.isEmpty {
                    ThinkingView(text: viewModel.currentThinkingText)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !viewModel.currentStreamingText.isEmpty {
                    // Use lightweight StreamingTextView during streaming to
                    // avoid expensive MarkdownContentView re-parses (WKWebView
                    // creation for LaTeX, code-block highlighting) on every
                    // single delta. The full MarkdownContentView is used once
                    // the message is finalized and saved to the messages array.
                    StreamingTextView(text: viewModel.currentStreamingText)
                } else if !viewModel.isThinking && viewModel.currentThinkingText.isEmpty {
                    TypingIndicator()
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)

            Spacer(minLength: 40)
        }
    }

    // MARK: - Recovery Banner

    private var recoveryBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Recovering interrupted response…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
