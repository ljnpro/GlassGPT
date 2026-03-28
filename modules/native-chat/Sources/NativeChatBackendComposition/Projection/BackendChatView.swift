import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import PhotosUI
import SwiftUI
import UIKit

/// Root chat tab view for the backend-owned Beta 5.0 shipping path.
package struct BackendChatView: View {
    @Bindable var viewModel: BackendChatController
    let openSettings: @MainActor () -> Void
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var showSelector = false
    @State private var composerResetToken = UUID()
    @State private var scrollRequestID = UUID()
    @State private var streamingThinkingExpanded: Bool? = true

    /// Creates the chat surface bound to a backend-owned projection controller.
    package init(
        viewModel: BackendChatController,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.openSettings = openSettings
    }

    /// The full chat navigation stack, message list, composer, and selector presentation flow.
    package var body: some View {
        NavigationStack {
            ChatScrollContainer(
                content: AnyView(
                    BackendChatMessageList(
                        viewModel: viewModel,
                        assistantBubbleMaxWidth: assistantBubbleMaxWidth,
                        streamingThinkingExpanded: $streamingThinkingExpanded,
                        openSettings: openSettings
                    )
                ),
                composer: AnyView(
                    BackendChatComposer(
                        viewModel: viewModel,
                        composerResetToken: composerResetToken,
                        onSendAccepted: { scrollRequestID = UUID() },
                        onPickImage: { showPhotoPicker = true },
                        onPickDocument: { showDocumentPicker = true }
                    )
                ),
                layoutMode: showsEmptyState ? .centered : .bottomAnchored,
                fixedBottomGap: 12,
                conversationID: viewModel.currentConversationID,
                scrollRequestID: scrollRequestID,
                liveBottomAnchorKey: liveBottomAnchorKey,
                onBackgroundTap: dismissKeyboard
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                BackendChatTopBar(
                    viewModel: viewModel,
                    onOpenSelector: {
                        dismissKeyboard()
                        showSelector = true
                    },
                    onStartNewConversation: {
                        composerResetToken = UUID()
                        scrollRequestID = UUID()
                        viewModel.startNewConversation()
                    }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .overFullScreenCover(
                isPresented: $showSelector,
                interfaceStyle: selectedTheme.colorScheme == .dark ? .dark : .light,
                onDismiss: dismissSelector
            ) {
                BackendChatSelectorOverlay(
                    viewModel: viewModel,
                    selectedTheme: selectedTheme,
                    onDismiss: dismissSelector
                )
            }
            .onChange(of: viewModel.currentConversationID) { _, _ in
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
                        Loggers.files.error("Failed to load photo: \(error.localizedDescription)")
                    }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { urls in
                    viewModel.handlePickedDocuments(urls)
                }
            }
            .task(id: viewModel.sessionAccountID) {
                guard !viewModel.skipAutomaticBootstrap else {
                    return
                }
                await viewModel.bootstrap()
            }
        }
    }

    private var showsEmptyState: Bool {
        viewModel.messages.isEmpty && !viewModel.isStreaming
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    private var assistantBubbleMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 680 : 520
    }

    private var liveBottomAnchorKey: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.currentConversationID)
        hasher.combine(viewModel.liveDraftMessageID)
        hasher.combine(viewModel.isThinking)
        hasher.combine(viewModel.isStreaming)
        hasher.combine(viewModel.currentThinkingText)
        hasher.combine(viewModel.currentStreamingText)
        return hasher.finalize()
    }

    private func dismissKeyboard() {
        KeyboardDismisser.dismiss()
    }

    private func dismissSelector() {
        showSelector = false
    }
}
