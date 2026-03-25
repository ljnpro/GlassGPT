import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import NativeChatUI
import PhotosUI
import SwiftUI
import UIKit

/// SwiftUI surface for the dedicated Agent mode transcript, progress UI, and composer.
package struct AgentView: View {
    @Bindable var viewModel: AgentController
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State var showPhotoPicker = false
    @State var selectedPhotoItem: PhotosPickerItem?
    @State var showDocumentPicker = false
    @State var composerResetToken = UUID()
    @State var isShowingAgentSelector = false
    @State var agentSelectorDraft = AgentConversationConfiguration()
    @State var liveSummaryExpanded: Bool? = true
    @State var scrollRequestID = UUID()
    @State var expandedTraceMessageIDs: Set<UUID> = []

    static let emptyConversationRootID = "agent.empty.root"

    /// Creates an Agent view backed by the given controller and optional expanded process-card state.
    package init(
        viewModel: AgentController,
        initialLiveSummaryExpanded: Bool? = true,
        initialExpandedTraceMessageIDs: Set<UUID> = []
    ) {
        self.viewModel = viewModel
        _liveSummaryExpanded = State(initialValue: initialLiveSummaryExpanded)
        _expandedTraceMessageIDs = State(initialValue: initialExpandedTraceMessageIDs)
    }

    /// The root Agent mode layout wrapped in a navigation stack.
    package var body: some View {
        NavigationStack {
            agentContent
                .id(viewRootIdentity)
                .toolbar(.hidden, for: .navigationBar)
                .overFullScreenCover(
                    isPresented: $isShowingAgentSelector,
                    interfaceStyle: agentSelectorInterfaceStyle,
                    onDismiss: dismissAgentSelector
                ) {
                    agentSelectorPresentation
                }
                .onChange(of: viewModel.currentConversation?.id) { _, _ in
                    liveSummaryExpanded = true
                    agentSelectorDraft = viewModel.currentConfiguration
                    composerResetToken = UUID()
                }
                .onAppear {
                    agentSelectorDraft = viewModel.currentConfiguration
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
        }
    }

    var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var agentSelectorInterfaceStyle: UIUserInterfaceStyle {
        switch selectedTheme {
        case .system:
            .unspecified
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
