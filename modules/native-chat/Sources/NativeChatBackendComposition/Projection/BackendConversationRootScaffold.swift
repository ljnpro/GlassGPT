import ChatDomain
import ChatUIComponents
import PhotosUI
import SwiftUI

/// Shared root scaffold used by backend-owned chat and agent surfaces.
package struct BackendConversationRootScaffold<Content: View, Composer: View, TopBar: View, Selector: View>: View {
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var showSelector = false
    @State private var composerResetToken = UUID()
    @State private var scrollRequestID = UUID()

    private let currentConversationID: UUID?
    private let sessionAccountID: String?
    private let skipAutomaticBootstrap: Bool
    private let presentsSelectorOnLaunch: Bool
    private let showsEmptyState: Bool
    private let liveBottomAnchorKey: Int
    private let selectedPhotoFailurePrefix: String
    private let onBootstrap: @MainActor () async -> Void
    private let onSelectedImageData: @MainActor (Data) -> Void
    private let onPickedDocuments: @MainActor ([URL]) -> Void
    private let onConversationChanged: @MainActor () -> Void
    private let onStartNewConversation: @MainActor () -> Void
    private let contentBuilder: @MainActor (CGFloat) -> Content
    private let composerBuilder: @MainActor (
        UUID,
        @escaping @MainActor () -> Void,
        @escaping @MainActor () -> Void,
        @escaping @MainActor () -> Void
    ) -> Composer
    private let topBarBuilder: @MainActor (
        @escaping @MainActor () -> Void,
        @escaping @MainActor () -> Void
    ) -> TopBar
    private let selectorBuilder: @MainActor (
        AppTheme,
        @escaping @MainActor () -> Void
    ) -> Selector

    /// Creates a backend conversation scaffold with shared chrome, picker, and bootstrap behavior.
    package init(
        currentConversationID: UUID?,
        sessionAccountID: String?,
        skipAutomaticBootstrap: Bool,
        presentsSelectorOnLaunch: Bool,
        showsEmptyState: Bool,
        liveBottomAnchorKey: Int,
        selectedPhotoFailurePrefix: String,
        onBootstrap: @escaping @MainActor () async -> Void,
        onSelectedImageData: @escaping @MainActor (Data) -> Void,
        onPickedDocuments: @escaping @MainActor ([URL]) -> Void,
        onConversationChanged: @escaping @MainActor () -> Void = {},
        onStartNewConversation: @escaping @MainActor () -> Void,
        content: @escaping @MainActor (CGFloat) -> Content,
        composer: @escaping @MainActor (
            UUID,
            @escaping @MainActor () -> Void,
            @escaping @MainActor () -> Void,
            @escaping @MainActor () -> Void
        ) -> Composer,
        topBar: @escaping @MainActor (
            @escaping @MainActor () -> Void,
            @escaping @MainActor () -> Void
        ) -> TopBar,
        selector: @escaping @MainActor (
            AppTheme,
            @escaping @MainActor () -> Void
        ) -> Selector
    ) {
        self.currentConversationID = currentConversationID
        self.sessionAccountID = sessionAccountID
        self.skipAutomaticBootstrap = skipAutomaticBootstrap
        self.presentsSelectorOnLaunch = presentsSelectorOnLaunch
        self.showsEmptyState = showsEmptyState
        self.liveBottomAnchorKey = liveBottomAnchorKey
        self.selectedPhotoFailurePrefix = selectedPhotoFailurePrefix
        self.onBootstrap = onBootstrap
        self.onSelectedImageData = onSelectedImageData
        self.onPickedDocuments = onPickedDocuments
        self.onConversationChanged = onConversationChanged
        self.onStartNewConversation = onStartNewConversation
        contentBuilder = content
        composerBuilder = composer
        topBarBuilder = topBar
        selectorBuilder = selector
    }

    package var body: some View {
        NavigationStack {
            ChatScrollContainer(
                content: contentBuilder(assistantBubbleMaxWidth),
                composer: composerBuilder(
                    composerResetToken,
                    { scrollRequestID = UUID() },
                    { showPhotoPicker = true },
                    { showDocumentPicker = true }
                ),
                layoutMode: showsEmptyState ? .centered : .bottomAnchored,
                fixedBottomGap: 12,
                conversationID: currentConversationID,
                scrollRequestID: scrollRequestID,
                liveBottomAnchorKey: liveBottomAnchorKey,
                onBackgroundTap: dismissKeyboard
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                topBarBuilder(
                    {
                        dismissKeyboard()
                        showSelector = true
                    },
                    startNewConversation
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .overFullScreenCover(
                isPresented: $showSelector,
                interfaceStyle: resolvedInterfaceStyle,
                onDismiss: dismissSelector
            ) {
                selectorBuilder(selectedTheme, dismissSelector)
            }
            .onChange(of: currentConversationID) { _, _ in
                composerResetToken = UUID()
                onConversationChanged()
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await BackendConversationViewSupport.loadSelectedPhoto(
                        newItem,
                        failurePrefix: selectedPhotoFailurePrefix,
                        assign: onSelectedImageData
                    )
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { urls in
                    onPickedDocuments(urls)
                }
            }
            .task(id: sessionAccountID) {
                guard !skipAutomaticBootstrap else {
                    return
                }
                await onBootstrap()
            }
            .onAppear {
                guard presentsSelectorOnLaunch, !showSelector else {
                    return
                }
                Task { @MainActor in
                    guard presentsSelectorOnLaunch else {
                        return
                    }
                    showSelector = true
                }
            }
        }
    }

    private var selectedTheme: AppTheme {
        BackendConversationViewSupport.selectedTheme(rawValue: appThemeRawValue)
    }

    private var resolvedInterfaceStyle: UIUserInterfaceStyle {
        BackendConversationViewSupport.resolvedInterfaceStyle(
            selectedTheme: selectedTheme,
            systemColorScheme: systemColorScheme
        )
    }

    private var assistantBubbleMaxWidth: CGFloat {
        BackendConversationViewSupport.assistantBubbleMaxWidth()
    }

    private func dismissKeyboard() {
        BackendConversationViewSupport.dismissKeyboard()
    }

    private func dismissSelector() {
        showSelector = false
    }

    private func startNewConversation() {
        composerResetToken = UUID()
        scrollRequestID = UUID()
        onStartNewConversation()
    }
}
