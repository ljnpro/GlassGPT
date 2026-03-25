import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import GeneratedFilesCore
import NativeChatUI
import PhotosUI
import SwiftUI
import UIKit

/// Main chat screen displaying the message list, composer bar, model selector, and generated file previews.
package struct ChatView: View {
    @Bindable var viewModel: ChatController
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State var showPhotoPicker = false
    @State var selectedPhotoItem: PhotosPickerItem?
    @State var showDocumentPicker = false
    @State var isShowingModelSelector = false
    @State var composerResetToken = UUID()
    @State var scrollRequestID = UUID()
    @State var streamingThinkingExpanded: Bool? = true
    @State var generatedPreview = GeneratedPreviewPresentationState()

    let generatedPreviewOverlayDismissDelay: UInt64 = 90_000_000
    let generatedPreviewTouchCooldownDuration: UInt64 = 1_000_000_000

    var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var modelSelectorInterfaceStyle: UIUserInterfaceStyle {
        switch selectedTheme {
        case .system:
            .unspecified
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    /// The composed chat screen content, including navigation, overlays, and previews.
    package var body: some View {
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
                .toolbar(.hidden, for: .navigationBar)
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
                    isPresented: $generatedPreview.isShowing,
                    interfaceStyle: modelSelectorInterfaceStyle,
                    onDismiss: handleGeneratedPreviewCoverDismiss
                ) {
                    if let previewItem = generatedPreview.presentedItem {
                        FilePreviewSheet(
                            previewItem: previewItem,
                            isDismissPending: generatedPreview.isDismissPending,
                            onBeginDismissInteraction: prepareGeneratedPreviewDismissal,
                            onRequestDismiss: beginGeneratedPreviewDismissal
                        )
                    } else {
                        Color.clear
                            .ignoresSafeArea()
                    }
                }
                .onChange(of: generatedPreviewCandidate?.id, initial: true) { _, _ in
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
                            Loggers.files.error("Failed to load photo: \(error.localizedDescription)")
                        }
                    }
                }
                .sheet(isPresented: $showDocumentPicker) {
                    DocumentPicker { urls in
                        viewModel.handlePickedDocuments(urls)
                    }
                }
                .alert(String(localized: "File Download Error"), isPresented: fileDownloadErrorBinding) {
                    Button(String(localized: "OK"), role: .cancel) {
                        viewModel.fileDownloadError = nil
                    }
                } message: {
                    Text(viewModel.fileDownloadError ?? String(localized: "An unknown error occurred."))
                }
                .onAppear {
                    syncGeneratedPreviewPresentation()
                }
                .onDisappear {
                    guard !generatedPreview.isShowing else { return }
                    generatedPreview.dismissTask?.cancel()
                    generatedPreview.dismissTask = nil
                    generatedPreview.isBlockingTouches = false
                    generatedPreview.presentedItem = nil
                    generatedPreview.isDismissPending = false
                    generatedPreview.isShowing = false
                }
                .allowsHitTesting(generatedPreview.presentedItem == nil && !generatedPreview.isBlockingTouches)
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

    /// Creates a chat view driven by the given chat controller.
    package init(viewModel: ChatController) {
        self.viewModel = viewModel
    }
}
