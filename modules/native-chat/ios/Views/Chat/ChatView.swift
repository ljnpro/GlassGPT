import SwiftUI
import PhotosUI
import UIKit

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var streamingThinkingExpanded: Bool? = true
    @State private var shouldFollowLiveOutput = true
    @State private var isNearBottom = true
    @State private var scrollViewportMaxY: CGFloat = 0
    @State private var bottomAnchorMaxY: CGFloat = 0

    private let autoFollowThreshold: CGFloat = 96

    var body: some View {
        NavigationStack {
            ZStack {
                chatContent

                // Restoring conversation overlay
                if viewModel.isRestoringConversation {
                    restoringOverlay
                        .transition(.opacity)
                }

                // File download overlay
                if viewModel.isDownloadingFile {
                    fileDownloadingOverlay
                        .transition(.opacity)
                }

                if viewModel.showModelSelector {
                    modelSelectorOverlay
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isRestoringConversation)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isDownloadingFile)
            .animation(.easeOut(duration: 0.18), value: viewModel.showModelSelector)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MessageInputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    selectedImageData: $viewModel.selectedImageData,
                    pendingAttachments: $viewModel.pendingAttachments,
                    onSend: { viewModel.sendMessage() },
                    onStop: { viewModel.stopGeneration() },
                    onPickImage: { showPhotoPicker = true },
                    onPickDocument: { showDocumentPicker = true },
                    onRemoveAttachment: { attachment in
                        viewModel.removePendingAttachment(attachment)
                    }
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
            .sheet(item: filePreviewBinding) { previewItem in
                FilePreviewSheet(fileURL: previewItem.url)
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
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { urls in
                    viewModel.handlePickedDocuments(urls)
                }
            }
            .alert("File Download Error", isPresented: fileDownloadErrorBinding) {
                Button("OK", role: .cancel) {
                    viewModel.fileDownloadError = nil
                }
            } message: {
                Text(viewModel.fileDownloadError ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - File Preview Binding

    private var filePreviewBinding: Binding<FilePreviewItem?> {
        Binding(
            get: {
                if let url = viewModel.filePreviewURL {
                    return FilePreviewItem(url: url)
                }
                return nil
            },
            set: { newValue in
                viewModel.filePreviewURL = newValue?.url
            }
        )
    }

    private var fileDownloadErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.fileDownloadError != nil },
            set: { if !$0 { viewModel.fileDownloadError = nil } }
        )
    }

    // MARK: - Chat Content

    @ViewBuilder
    private var chatContent: some View {
        if viewModel.messages.isEmpty && !viewModel.isStreaming && !viewModel.isRestoringConversation {
            emptyState
        } else {
            ScrollViewReader { proxy in
                chatScrollView(proxy)
            }
        }
    }

    private func chatScrollView(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.messages) { message in
                    messageRow(for: message)
                }

                if viewModel.shouldShowDetachedStreamingBubble {
                    streamingBubble
                        .id("streaming")
                }

                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                Color.clear.frame(height: 1)
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: ChatBottomAnchorMaxYPreferenceKey.self,
                                    value: geometry.frame(in: .global).maxY
                                )
                        }
                    }
                    .id("bottom")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: ChatViewportMaxYPreferenceKey.self,
                        value: geometry.frame(in: .global).maxY
                    )
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            DragGesture()
                .onChanged { _ in
                    if !isNearBottom {
                        shouldFollowLiveOutput = false
                    }
                }
                .onEnded { _ in
                    shouldFollowLiveOutput = isNearBottom
                }
        )
        .onPreferenceChange(ChatViewportMaxYPreferenceKey.self) { value in
            scrollViewportMaxY = value
            updateBottomFollowState()
        }
        .onPreferenceChange(ChatBottomAnchorMaxYPreferenceKey.self) { value in
            bottomAnchorMaxY = value
            updateBottomFollowState()
        }
        .onChange(of: viewModel.currentStreamingText) { _, _ in
            scrollToLiveTargetIfNeeded(proxy, animated: true)
        }
        .onChange(of: viewModel.currentThinkingText) { _, _ in
            scrollToLiveTargetIfNeeded(proxy, animated: true)
        }
        .onChange(of: viewModel.messages.count) { _, _ in
            scrollToLiveTargetIfNeeded(proxy, animated: true)
        }
        .onChange(of: viewModel.activeToolCalls.count) { _, _ in
            scrollToLiveTargetIfNeeded(proxy, animated: true)
        }
        .onChange(of: viewModel.isStreaming) { _, newValue in
            if newValue {
                streamingThinkingExpanded = true
                shouldFollowLiveOutput = true
                scrollToLiveTargetIfNeeded(proxy, animated: false)
            }
        }
        .onChange(of: viewModel.isRecovering) { _, newValue in
            if newValue {
                shouldFollowLiveOutput = true
                scrollToLiveTargetIfNeeded(proxy, animated: false)
            }
        }
    }

    private func messageRow(for message: Message) -> some View {
        let isLiveDraft = viewModel.liveDraftMessageID == message.id

        return MessageBubble(
            message: message,
            onRegenerate: message.role == .assistant ? {
                viewModel.regenerateMessage(message)
            } : nil,
            liveContent: isLiveDraft ? viewModel.currentStreamingText : nil,
            liveThinking: isLiveDraft ? viewModel.currentThinkingText : nil,
            activeToolCalls: isLiveDraft ? viewModel.activeToolCalls : [],
            liveCitations: isLiveDraft ? viewModel.liveCitations : [],
            liveFilePathAnnotations: isLiveDraft ? viewModel.liveFilePathAnnotations : [],
            showsRecoveryIndicator: isLiveDraft && viewModel.isRecovering,
            onSandboxLinkTap: message.role == .assistant ? { sandboxURL, annotation in
                viewModel.handleSandboxLinkTap(message: message, sandboxURL: sandboxURL, annotation: annotation)
            } : nil
        )
        .id(message.id)
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

    // MARK: - File Downloading Overlay

    private var fileDownloadingOverlay: some View {
        VStack(spacing: 12) {
            Spacer()

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading file…")
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
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    private var modelSelectorOverlay: some View {
        GeometryReader { geometry in
            let idiom = UIDevice.current.userInterfaceIdiom
            let horizontalInset = idiom == .pad ? 32.0 : 16.0
            let maxPanelWidth = idiom == .pad ? 680.0 : min(geometry.size.width - (horizontalInset * 2), 520.0)
            let topInset = idiom == .pad ? 18.0 : 12.0

            ZStack(alignment: .top) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.showModelSelector = false
                    }

                ModelSelectorSheet(
                    proModeEnabled: Binding(
                        get: { viewModel.proModeEnabled },
                        set: { viewModel.proModeEnabled = $0 }
                    ),
                    backgroundModeEnabled: $viewModel.backgroundModeEnabled,
                    flexModeEnabled: Binding(
                        get: { viewModel.flexModeEnabled },
                        set: { viewModel.flexModeEnabled = $0 }
                    ),
                    reasoningEffort: $viewModel.reasoningEffort,
                    onDone: { viewModel.showModelSelector = false }
                )
                .frame(maxWidth: maxPanelWidth)
                .padding(.top, topInset)
                .padding(.horizontal, horizontalInset)
            }
        }
    }

    // MARK: - Streaming Bubble

    private var streamingBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                // Active tool call indicators — DEDUPLICATED
                // Only show ONE web search indicator, regardless of how many web search calls are active
                let hasActiveWebSearch = viewModel.activeToolCalls.contains {
                    $0.type == .webSearch && $0.status != .completed
                }
                if hasActiveWebSearch {
                    WebSearchIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Only show ONE code interpreter indicator
                let hasActiveCodeInterpreter = viewModel.activeToolCalls.contains {
                    $0.type == .codeInterpreter && $0.status != .completed
                }
                if hasActiveCodeInterpreter {
                    CodeInterpreterIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Only show ONE file search indicator
                let hasActiveFileSearch = viewModel.activeToolCalls.contains {
                    $0.type == .fileSearch && $0.status != .completed
                }
                if hasActiveFileSearch {
                    FileSearchIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Completed code interpreter results (during streaming)
                let completedCodeCalls = viewModel.activeToolCalls.filter {
                    $0.type == .codeInterpreter && $0.status == .completed
                }
                ForEach(completedCodeCalls) { toolCall in
                    CodeInterpreterResultView(toolCall: toolCall)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if viewModel.isThinking {
                    ThinkingIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Live thinking text — collapsible, starts expanded during streaming
                if !viewModel.currentThinkingText.isEmpty {
                    ThinkingView(
                        text: viewModel.currentThinkingText,
                        isLive: viewModel.isThinking || viewModel.isStreaming,
                        externalIsExpanded: $streamingThinkingExpanded
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !viewModel.currentStreamingText.isEmpty {
                    StreamingTextView(text: viewModel.currentStreamingText)
                } else if !viewModel.isThinking && viewModel.currentThinkingText.isEmpty
                            && viewModel.activeToolCalls.allSatisfy({ $0.status == .completed }) {
                    TypingIndicator()
                }

                // Live citations during streaming
                if !viewModel.liveCitations.isEmpty {
                    CitationLinksView(citations: viewModel.liveCitations)
                }
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)

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

private extension ChatView {
    var assistantBubbleMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 680 : 520
    }

    func updateBottomFollowState() {
        guard scrollViewportMaxY > 0 else { return }

        let distanceToBottom = bottomAnchorMaxY - scrollViewportMaxY
        let nextIsNearBottom = distanceToBottom <= autoFollowThreshold

        if nextIsNearBottom != isNearBottom {
            isNearBottom = nextIsNearBottom
        }

        if nextIsNearBottom {
            shouldFollowLiveOutput = true
        }
    }

    func scrollToLiveTargetIfNeeded(_ proxy: ScrollViewProxy, animated: Bool) {
        guard shouldFollowLiveOutput || isNearBottom else { return }

        let scrollAction = {
            if let liveDraftMessageID = viewModel.liveDraftMessageID {
                proxy.scrollTo(liveDraftMessageID, anchor: .bottom)
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }

        if animated {
            withAnimation(.easeOut(duration: 0.18), scrollAction)
        } else {
            scrollAction()
        }
    }
}

private struct ChatViewportMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatBottomAnchorMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - File Preview Item

struct FilePreviewItem: Identifiable {
    let url: URL

    var id: String { url.path }
}
