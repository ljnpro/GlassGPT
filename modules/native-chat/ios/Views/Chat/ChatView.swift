import PhotosUI
import SwiftUI
import UIKit

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State var showPhotoPicker = false
    @State var selectedPhotoItem: PhotosPickerItem?
    @State var showDocumentPicker = false
    @State var isShowingModelSelector = false
    @State var composerResetToken = UUID()
    @State var modelSelectorDraft = ConversationConfiguration(
        model: .gpt5_4,
        reasoningEffort: .high,
        backgroundModeEnabled: false,
        serviceTier: .standard
    )
    @State var scrollRequestID = UUID()
    @State var streamingThinkingExpanded: Bool? = true
    @State var isBlockingGeneratedPreviewTouches = false
    @State var presentedGeneratedPreviewItem: FilePreviewItem?
    @State var isGeneratedPreviewDismissPending = false
    @State var isShowingGeneratedPreview = false
    @State var generatedPreviewDismissTask: Task<Void, Never>?

    let generatedPreviewOverlayDismissDelay: UInt64 = 90_000_000
    let generatedPreviewTouchCooldownDuration: UInt64 = 1_000_000_000

    var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var modelSelectorInterfaceStyle: UIUserInterfaceStyle {
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
                        .accessibilityIdentifier("chat.newChat")
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
                    guard !isShowingGeneratedPreview else { return }
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
}
