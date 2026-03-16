import SwiftUI
import PhotosUI
import UIKit

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var isShowingModelSelector = false
    @State private var composerResetToken = UUID()
    @State private var modelSelectorDraft = ConversationConfiguration(
        model: .gpt5_4,
        reasoningEffort: .high,
        backgroundModeEnabled: false,
        serviceTier: .standard
    )
    @State private var scrollRequestID = UUID()
    @State private var streamingThinkingExpanded: Bool? = true
    @State private var isBlockingGeneratedPreviewTouches = false
    @State private var presentedGeneratedPreviewItem: FilePreviewItem?
    @State private var isGeneratedPreviewDismissPending = false
    @State private var isShowingGeneratedPreview = false
    @State private var generatedPreviewDismissTask: Task<Void, Never>?

    private let generatedPreviewOverlayDismissDelay: UInt64 = 90_000_000
    private let generatedPreviewTouchCooldownDuration: UInt64 = 1_000_000_000

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    private var modelSelectorInterfaceStyle: UIUserInterfaceStyle {
        switch selectedTheme {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    chatContent

                    if viewModel.isRestoringConversation {
                        restoringOverlay
                            .transition(.opacity)
                    }

                    if viewModel.isDownloadingFile {
                        fileDownloadingOverlay
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: viewModel.isRestoringConversation)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isDownloadingFile)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ModelBadge(
                            model: viewModel.selectedModel,
                            effort: viewModel.reasoningEffort,
                            onTap: { presentModelSelector() }
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .allowsHitTesting(!shouldShowGeneratedPreviewTouchShield)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            startNewChat()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .singleFrameGlassCapsuleControl(
                                    tintOpacity: 0.015,
                                    borderWidth: 0.78,
                                    darkBorderOpacity: 0.14,
                                    lightBorderOpacity: 0.08
                                )
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .accessibilityLabel("New Chat")
                        .allowsHitTesting(!shouldShowGeneratedPreviewTouchShield)
                    }
                }
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .sheet(item: sharedGeneratedFileBinding) { sharedItem in
                    ActivityViewController(activityItems: [sharedItem.url])
                }
                .overFullScreenCover(
                    isPresented: $isShowingModelSelector,
                    interfaceStyle: modelSelectorInterfaceStyle,
                    onDismiss: dismissModelSelector
                ) {
                    modelSelectorPresentation
                }
                .overFullScreenCover(
                    isPresented: $isShowingGeneratedPreview,
                    interfaceStyle: modelSelectorInterfaceStyle,
                    onDismiss: handleGeneratedPreviewCoverDismiss
                ) {
                    if let previewItem = presentedGeneratedPreviewItem {
                        FilePreviewSheet(
                            previewItem: previewItem,
                            isDismissPending: isGeneratedPreviewDismissPending,
                            onBeginDismissInteraction: prepareGeneratedPreviewDismissal,
                            onRequestDismiss: beginGeneratedPreviewDismissal
                        )
                    } else {
                        Color.clear
                            .ignoresSafeArea()
                    }
                }
                .onChange(of: generatedPreviewCandidate?.id) { _, _ in
                    syncGeneratedPreviewPresentation()
                }
                .onChange(of: viewModel.currentConversation?.id) { _, _ in
                    composerResetToken = UUID()
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
                .onAppear {
                    syncGeneratedPreviewPresentation()
                }
                .onDisappear {
                    generatedPreviewDismissTask?.cancel()
                    generatedPreviewDismissTask = nil
                    isBlockingGeneratedPreviewTouches = false
                    presentedGeneratedPreviewItem = nil
                    isGeneratedPreviewDismissPending = false
                    isShowingGeneratedPreview = false
                }
                .allowsHitTesting(presentedGeneratedPreviewItem == nil && !isBlockingGeneratedPreviewTouches)
            }
            if shouldShowGeneratedPreviewTouchShield {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                    .zIndex(1500)
            }
        }
    }

    // MARK: - File Preview Binding

    private var sharedGeneratedFileBinding: Binding<SharedGeneratedFileItem?> {
        Binding(
            get: {
                viewModel.sharedGeneratedFileItem
            },
            set: { newValue in
                if let newValue {
                    viewModel.sharedGeneratedFileItem = newValue
                } else {
                    viewModel.sharedGeneratedFileItem = nil
                }
            }
        )
    }

    private var generatedPreviewCandidate: FilePreviewItem? {
        guard let previewItem = viewModel.filePreviewItem else { return nil }
        switch previewItem.kind {
        case .generatedImage, .generatedPDF:
            return previewItem
        }
    }

    private var fileDownloadErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.fileDownloadError != nil },
            set: { if !$0 { viewModel.fileDownloadError = nil } }
        )
    }

    private var shouldShowGeneratedPreviewTouchShield: Bool {
        presentedGeneratedPreviewItem != nil || isBlockingGeneratedPreviewTouches
    }

    // MARK: - Chat Content

    @ViewBuilder
    private var chatContent: some View {
        ChatScrollContainer(
            content: AnyView(chatMessagesContent),
            composer: AnyView(messageInputBar),
            layoutMode: showsEmptyState ? .centered : .bottomAnchored,
            fixedBottomGap: 12,
            conversationID: viewModel.currentConversation?.id,
            scrollRequestID: scrollRequestID,
            onBackgroundTap: dismissKeyboard
        )
    }

    private var chatMessagesContent: some View {
        Group {
            if showsEmptyState {
                emptyState
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        messageRow(for: message)
                    }

                    if viewModel.shouldShowDetachedStreamingBubble {
                        streamingBubble
                    }

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private var messageInputBar: some View {
        MessageInputBar(
            resetToken: composerResetToken,
            isStreaming: viewModel.isStreaming,
            selectedImageData: $viewModel.selectedImageData,
            pendingAttachments: $viewModel.pendingAttachments,
            onSend: { text in
                let didSend = viewModel.sendMessage(text: text)
                if didSend {
                    scrollRequestID = UUID()
                }
                return didSend
            },
            onStop: { viewModel.stopGeneration() },
            onPickImage: { showPhotoPicker = true },
            onPickDocument: { showDocumentPicker = true },
            onRemoveAttachment: { attachment in
                viewModel.removePendingAttachment(attachment)
            }
        )
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
        .equatable()
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
            .singleSurfaceGlass(
                cornerRadius: 999,
                stableFillOpacity: 0.012,
                borderWidth: 0.8,
                darkBorderOpacity: 0.14,
                lightBorderOpacity: 0.08
            )

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
            .singleSurfaceGlass(
                cornerRadius: 999,
                stableFillOpacity: 0.012,
                borderWidth: 0.8,
                darkBorderOpacity: 0.14,
                lightBorderOpacity: 0.08
            )

            Spacer()
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

            if !viewModel.hasAPIKey {
                Label("Add your API key in Settings", systemImage: "key.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }

    private var modelSelectorPresentation: some View {
        GeometryReader { geometry in
            let idiom = UIDevice.current.userInterfaceIdiom
            let horizontalInset = idiom == .pad ? 32.0 : 16.0
            let maxPanelWidth = idiom == .pad ? 680.0 : min(geometry.size.width - (horizontalInset * 2), 520.0)
            let topInset = idiom == .pad ? 76.0 : 60.0

            ZStack(alignment: .top) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissModelSelector()
                    }

                ModelSelectorSheet(
                    proModeEnabled: Binding(
                        get: { modelSelectorDraft.proModeEnabled },
                        set: { modelSelectorDraft.proModeEnabled = $0 }
                    ),
                    backgroundModeEnabled: $modelSelectorDraft.backgroundModeEnabled,
                    flexModeEnabled: Binding(
                        get: { modelSelectorDraft.flexModeEnabled },
                        set: { modelSelectorDraft.flexModeEnabled = $0 }
                    ),
                    reasoningEffort: $modelSelectorDraft.reasoningEffort,
                    onDone: commitModelSelectorAndDismiss
                )
                .frame(maxWidth: maxPanelWidth)
                .padding(.top, topInset)
                .padding(.horizontal, horizontalInset)
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }

    // MARK: - Streaming Bubble

    private var streamingBubble: some View {
        DetachedStreamingBubbleView(
            activeToolCalls: viewModel.activeToolCalls,
            currentThinkingText: viewModel.currentThinkingText,
            currentStreamingText: viewModel.currentStreamingText,
            isThinking: viewModel.isThinking,
            isStreaming: viewModel.isStreaming,
            liveCitations: viewModel.liveCitations,
            streamingThinkingExpanded: $streamingThinkingExpanded,
            assistantBubbleMaxWidth: assistantBubbleMaxWidth
        )
        .equatable()
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
        .singleSurfaceGlass(
            cornerRadius: 12,
            stableFillOpacity: 0.01,
            borderWidth: 0.75,
            darkBorderOpacity: 0.14,
            lightBorderOpacity: 0.08
        )
    }
}

private struct DetachedStreamingBubbleView: View, Equatable {
    let activeToolCalls: [ToolCallInfo]
    let currentThinkingText: String
    let currentStreamingText: String
    let isThinking: Bool
    let isStreaming: Bool
    let liveCitations: [URLCitation]
    @Binding var streamingThinkingExpanded: Bool?
    let assistantBubbleMaxWidth: CGFloat
    private let renderKey: RenderKey

    init(
        activeToolCalls: [ToolCallInfo],
        currentThinkingText: String,
        currentStreamingText: String,
        isThinking: Bool,
        isStreaming: Bool,
        liveCitations: [URLCitation],
        streamingThinkingExpanded: Binding<Bool?>,
        assistantBubbleMaxWidth: CGFloat
    ) {
        self.activeToolCalls = activeToolCalls
        self.currentThinkingText = currentThinkingText
        self.currentStreamingText = currentStreamingText
        self.isThinking = isThinking
        self.isStreaming = isStreaming
        self.liveCitations = liveCitations
        self._streamingThinkingExpanded = streamingThinkingExpanded
        self.assistantBubbleMaxWidth = assistantBubbleMaxWidth
        self.renderKey = RenderKey(
            activeToolCalls: activeToolCalls,
            currentThinkingText: currentThinkingText,
            currentStreamingText: currentStreamingText,
            isThinking: isThinking,
            isStreaming: isStreaming,
            liveCitations: liveCitations,
            assistantBubbleMaxWidth: assistantBubbleMaxWidth
        )
    }

    nonisolated static func == (lhs: DetachedStreamingBubbleView, rhs: DetachedStreamingBubbleView) -> Bool {
        lhs.renderKey == rhs.renderKey
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                let hasActiveWebSearch = activeToolCalls.contains {
                    $0.type == .webSearch && $0.status != .completed
                }
                if hasActiveWebSearch {
                    WebSearchIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                let hasActiveCodeInterpreter = activeToolCalls.contains {
                    $0.type == .codeInterpreter && $0.status != .completed
                }
                if hasActiveCodeInterpreter {
                    CodeInterpreterIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                let hasActiveFileSearch = activeToolCalls.contains {
                    $0.type == .fileSearch && $0.status != .completed
                }
                if hasActiveFileSearch {
                    FileSearchIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                let completedCodeCalls = activeToolCalls.filter {
                    $0.type == .codeInterpreter && $0.status == .completed
                }
                ForEach(completedCodeCalls) { toolCall in
                    CodeInterpreterResultView(toolCall: toolCall)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isThinking {
                    ThinkingIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                if !currentThinkingText.isEmpty {
                    ThinkingView(
                        text: currentThinkingText,
                        isLive: isThinking || isStreaming,
                        externalIsExpanded: $streamingThinkingExpanded
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !currentStreamingText.isEmpty {
                    StreamingTextView(
                        text: currentStreamingText,
                        allowsSelection: false
                    )
                } else if !isThinking && currentThinkingText.isEmpty
                            && activeToolCalls.allSatisfy({ $0.status == .completed }) {
                    TypingIndicator()
                }

                if !liveCitations.isEmpty {
                    CitationLinksView(citations: liveCitations)
                }
            }
            .padding(12)
            .singleSurfaceGlass(
                cornerRadius: 20,
                stableFillOpacity: 0.01,
                tintOpacity: 0.016,
                lightGlassTone: .neutral,
                backdropStyle: .themeSolid,
                borderWidth: 0.85,
                darkBorderOpacity: 0.16,
                lightBorderOpacity: 0.09
            )
            .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)

            Spacer(minLength: 40)
        }
    }
}

private extension DetachedStreamingBubbleView {
    struct RenderKey: Equatable {
        let activeToolCalls: [ToolCallInfo]
        let currentThinkingText: String
        let currentStreamingText: String
        let isThinking: Bool
        let isStreaming: Bool
        let liveCitations: [URLCitation]
        let assistantBubbleMaxWidth: CGFloat
    }
}

private extension ChatView {
    var showsEmptyState: Bool {
        viewModel.messages.isEmpty && !viewModel.isStreaming && !viewModel.isRestoringConversation
    }

    var assistantBubbleMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 680 : 520
    }

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func syncGeneratedPreviewPresentation() {
        guard let previewItem = generatedPreviewCandidate else {
            guard !isGeneratedPreviewDismissPending else { return }
            isShowingGeneratedPreview = false
            presentedGeneratedPreviewItem = nil
            isBlockingGeneratedPreviewTouches = false
            return
        }

        generatedPreviewDismissTask?.cancel()
        generatedPreviewDismissTask = nil
        presentedGeneratedPreviewItem = previewItem
        isGeneratedPreviewDismissPending = false
        isBlockingGeneratedPreviewTouches = false
        if !isShowingGeneratedPreview {
            isShowingGeneratedPreview = true
        }
    }

    func prepareGeneratedPreviewDismissal() {
        guard presentedGeneratedPreviewItem != nil else { return }
        guard !isGeneratedPreviewDismissPending else { return }
        generatedPreviewDismissTask?.cancel()
        generatedPreviewDismissTask = nil
        isGeneratedPreviewDismissPending = true
        isBlockingGeneratedPreviewTouches = true
    }

    func beginGeneratedPreviewDismissal() {
        guard presentedGeneratedPreviewItem != nil else { return }
        if !isGeneratedPreviewDismissPending {
            prepareGeneratedPreviewDismissal()
        }

        viewModel.filePreviewItem = nil

        generatedPreviewDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: generatedPreviewOverlayDismissDelay)
            isShowingGeneratedPreview = false

            try? await Task.sleep(nanoseconds: generatedPreviewTouchCooldownDuration)
            presentedGeneratedPreviewItem = nil
            isBlockingGeneratedPreviewTouches = false
            isGeneratedPreviewDismissPending = false
            generatedPreviewDismissTask = nil
        }
    }

    func handleGeneratedPreviewCoverDismiss() {
        guard !isShowingGeneratedPreview else { return }

        if !isGeneratedPreviewDismissPending {
            presentedGeneratedPreviewItem = nil
            isBlockingGeneratedPreviewTouches = false
            generatedPreviewDismissTask?.cancel()
            generatedPreviewDismissTask = nil
            viewModel.filePreviewItem = nil
        }
    }

    func presentModelSelector() {
        dismissKeyboard()
        modelSelectorDraft = viewModel.conversationConfiguration
        isShowingModelSelector = true
    }

    func startNewChat() {
        composerResetToken = UUID()
        viewModel.startNewChat()
    }

    func dismissModelSelector() {
        isShowingModelSelector = false
    }

    func commitModelSelectorAndDismiss() {
        viewModel.applyConversationConfiguration(modelSelectorDraft)
        dismissModelSelector()
    }
}
