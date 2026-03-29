import ChatDomain
import ChatPersistenceCore
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import PhotosUI
import SwiftUI
import UIKit

/// Root agent tab view for the backend-owned Beta 5.0 shipping path.
package struct BackendAgentView: View {
    @Bindable var viewModel: BackendAgentController
    let openSettings: @MainActor () -> Void
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var showSelector = false
    @State private var composerResetToken = UUID()
    @State private var scrollRequestID = UUID()
    @State private var liveSummaryExpanded: Bool? = true
    @State private var streamingThinkingExpanded: Bool? = nil
    @State private var expandedTraceMessageIDs: Set<UUID> = []

    /// Creates the agent surface bound to a backend-owned projection controller.
    package init(
        viewModel: BackendAgentController,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.openSettings = openSettings
    }

    /// The full agent navigation stack, composer, selector, and live summary presentation flow.
    package var body: some View {
        NavigationStack {
            ChatScrollContainer(
                content: AnyView(
                    BackendAgentMessageList(
                        viewModel: viewModel,
                        assistantBubbleMaxWidth: assistantBubbleMaxWidth,
                        liveSummaryExpanded: $liveSummaryExpanded,
                        streamingThinkingExpanded: $streamingThinkingExpanded,
                        expandedTraceMessageIDs: $expandedTraceMessageIDs,
                        openSettings: openSettings
                    )
                ),
                composer: AnyView(
                    BackendAgentComposer(
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
                BackendAgentTopBar(
                    viewModel: viewModel,
                    onOpenSelector: {
                        dismissKeyboard()
                        showSelector = true
                    },
                    onStartNewConversation: {
                        composerResetToken = UUID()
                        scrollRequestID = UUID()
                        expandedTraceMessageIDs.removeAll()
                        viewModel.startNewConversation()
                    }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .overFullScreenCover(
                isPresented: $showSelector,
                interfaceStyle: resolvedInterfaceStyle,
                onDismiss: dismissSelector
            ) {
                BackendAgentSelectorOverlay(
                    viewModel: viewModel,
                    selectedTheme: selectedTheme,
                    onDismiss: dismissSelector
                )
            }
            .onChange(of: viewModel.currentConversationID) { _, _ in
                liveSummaryExpanded = true
                streamingThinkingExpanded = nil
                composerResetToken = UUID()
                expandedTraceMessageIDs.removeAll()
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
                        Loggers.files.error("Failed to load Agent photo: \(error.localizedDescription)")
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
            .onAppear {
                guard viewModel.presentsSelectorOnLaunch, !showSelector else {
                    return
                }
                DispatchQueue.main.async {
                    guard viewModel.presentsSelectorOnLaunch else {
                        return
                    }
                    showSelector = true
                }
            }
        }
    }

    private var showsEmptyState: Bool {
        viewModel.messages.isEmpty && !viewModel.isRunning
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    private var resolvedInterfaceStyle: UIUserInterfaceStyle {
        if let explicit = selectedTheme.colorScheme {
            return explicit == .dark ? .dark : .light
        }
        return systemColorScheme == .dark ? .dark : .light
    }

    private var assistantBubbleMaxWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 680 : 520
    }

    private var liveBottomAnchorKey: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.currentConversationID)
        hasher.combine(viewModel.liveDraftMessageID)
        hasher.combine(viewModel.processSnapshot.activity.rawValue)
        hasher.combine(viewModel.currentStreamingText)
        hasher.combine(viewModel.currentThinkingText)
        hasher.combine(viewModel.isRunning)
        hasher.combine(viewModel.isThinking)
        hasher.combine(viewModel.activeToolCalls.count)
        hasher.combine(viewModel.liveCitations.count)
        hasher.combine(viewModel.liveFilePathAnnotations.count)
        hasher.combine(viewModel.processSnapshot.currentFocus)
        hasher.combine(viewModel.processSnapshot.leaderAcceptedFocus)
        hasher.combine(viewModel.processSnapshot.leaderLiveStatus)
        hasher.combine(viewModel.processSnapshot.leaderLiveSummary)
        hasher.combine(viewModel.processSnapshot.recoveryState.rawValue)
        hasher.combine(viewModel.processSnapshot.recentUpdateItems.count)
        hasher.combine(viewModel.processSnapshot.events.count)
        hasher.combine(viewModel.processSnapshot.tasks.count)
        hasher.combine(viewModel.processSnapshot.activeTaskIDs.count)
        hasher.combine(viewModel.processSnapshot.decisions.count)
        for update in viewModel.processSnapshot.recentUpdateItems {
            hasher.combine(update.id)
            hasher.combine(update.kind.rawValue)
            hasher.combine(update.summary)
        }
        for taskID in viewModel.processSnapshot.activeTaskIDs {
            hasher.combine(taskID)
        }
        for task in viewModel.processSnapshot.tasks {
            hasher.combine(task.id)
            hasher.combine(task.status.rawValue)
            hasher.combine(task.liveStatusText ?? "")
            hasher.combine(task.liveSummary ?? "")
            hasher.combine(task.resultSummary ?? "")
        }
        for toolCall in viewModel.activeToolCalls {
            hasher.combine(toolCall.id)
            hasher.combine(toolCall.status.rawValue)
        }
        return hasher.finalize()
    }

    private func dismissKeyboard() {
        KeyboardDismisser.dismiss()
    }

    private func dismissSelector() {
        showSelector = false
    }
}
