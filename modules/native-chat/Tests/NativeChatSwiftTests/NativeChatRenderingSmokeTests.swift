import ChatDomain
import ChatPresentation
import ChatProjectionPersistence
import Foundation
import GeneratedFilesCore
import SwiftData
import SwiftUI
import Testing
@testable import NativeChatBackendComposition
@testable import NativeChatBackendCore
@testable import NativeChatUI

@Suite(.tags(.presentation))
@MainActor
struct NativeChatRenderingSmokeTests {
    @Test func `settings history and selector surfaces host without crashing`() throws {
        let signedInHarness = try makeNativeChatHarness(signedIn: true)
        let signedOutHarness = try makeNativeChatHarness(signedIn: false)

        hostView(SettingsView(viewModel: signedInHarness.settingsPresenter))
        hostView(SettingsChatDefaultsSection(viewModel: signedInHarness.settingsPresenter.defaults))
        hostView(SettingsAppearanceSection(viewModel: signedInHarness.settingsPresenter.defaults))
        hostView(SettingsAgentDefaultsView(viewModel: signedInHarness.settingsPresenter.agentDefaults))
        hostView(
            SettingsCacheSection(
                title: "Generated Images",
                usedValue: "12 KB",
                footerText: "Footer",
                isClearing: false,
                hasCachedContent: true,
                clearLabel: "Clear"
            ) {}
        )
        hostView(SettingsAboutSection(appVersionString: "5.0.0 (50000)", platformString: "iOS 26.4"))

        let signedOutHistory = HistoryPresenter(
            loadConversations: { [] },
            selectConversation: { _, _ in },
            isSignedIn: { false },
            openSettings: {}
        )
        let signedInHistory = HistoryPresenter(
            conversations: [
                HistoryConversationSummary(
                    id: "conv_1",
                    mode: .chat,
                    title: "Release",
                    preview: "Preview",
                    updatedAt: .now,
                    modelDisplayName: "GPT-5.4"
                )
            ],
            loadConversations: { [] },
            selectConversation: { _, _ in },
            isSignedIn: { true },
            openSettings: {}
        )
        hostView(HistoryView(store: signedOutHistory))
        hostView(HistoryView(store: signedInHistory))

        try? FileManager.default.removeItem(at: signedInHarness.cacheRoot)
        try? FileManager.default.removeItem(at: signedOutHarness.cacheRoot)
    }

    @Test func `preview input and root surfaces host without crashing`() throws {
        let signedInHarness = try makeNativeChatHarness(signedIn: true)
        let signedOutHarness = try makeNativeChatHarness(signedIn: false)

        var selectedImageData: Data? = Data([0x01])
        var pendingAttachments = [FileAttachment(filename: "report.pdf", fileType: "pdf")]
        hostView(
            MessageInputBar(
                resetToken: UUID(),
                isStreaming: false,
                selectedImageData: Binding<Data?>(get: { selectedImageData }, set: { selectedImageData = $0 }),
                pendingAttachments: Binding(get: { pendingAttachments }, set: { pendingAttachments = $0 }),
                onSend: { _ in true },
                onStop: {},
                onPickImage: {},
                onPickDocument: {},
                onRemoveAttachment: { attachment in
                    pendingAttachments.removeAll { $0.id == attachment.id }
                }
            )
        )

        let imageURL = try makeSnapshotImageFile()
        let pdfURL = try makeSnapshotPDFFile()
        hostView(
            FilePreviewSheet(
                previewItem: FilePreviewItem(
                    url: imageURL,
                    kind: .generatedImage,
                    displayName: "Image",
                    viewerFilename: "image.png"
                )
            ),
            runLoopDelay: 0.4
        )
        hostView(
            FilePreviewSheet(
                previewItem: FilePreviewItem(
                    url: pdfURL,
                    kind: .generatedPDF,
                    displayName: "PDF",
                    viewerFilename: "report.pdf"
                )
            ),
            runLoopDelay: 0.4
        )

        let schema = Schema([Conversation.self, Message.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let previousConsent = UserDefaults.standard.object(forKey: "hasAcceptedDataSharing")
        UserDefaults.standard.set(true, forKey: "hasAcceptedDataSharing")
        defer {
            try? FileManager.default.removeItem(at: signedInHarness.cacheRoot)
            try? FileManager.default.removeItem(at: signedOutHarness.cacheRoot)
            if let previousConsent {
                UserDefaults.standard.set(previousConsent, forKey: "hasAcceptedDataSharing")
            } else {
                UserDefaults.standard.removeObject(forKey: "hasAcceptedDataSharing")
            }
        }

        hostView(
            NativeChatRootView(rootOverrideFactory: OverrideRootFactory())
                .modelContainer(container)
        )
    }

    @Test func `backend composition chat surfaces host without crashing`() throws {
        let signedOutHarness = try makeNativeChatHarness(signedIn: false)
        let chatController = signedOutHarness.makeChatController()

        hostBackendChatSurfaces(for: chatController)
        try? FileManager.default.removeItem(at: signedOutHarness.cacheRoot)
    }

    @Test func `backend composition agent and shell surfaces host without crashing`() throws {
        let signedOutHarness = try makeNativeChatHarness(signedIn: false)
        let signedInHarness = try makeNativeChatHarness(signedIn: true)
        let populatedAgentController = signedInHarness.makeAgentController()
        populatedAgentController.messages = [makeBackendMessageSurface(isComplete: false, includeTrace: true)]
        populatedAgentController.isRunning = true
        populatedAgentController.isThinking = true
        populatedAgentController.processSnapshot = AgentProcessSnapshot(
            activity: .synthesis,
            currentFocus: "Synthesize",
            leaderLiveStatus: "Working",
            leaderLiveSummary: "Combining results"
        )

        hostBackendAgentSurfaces(
            populatedAgentController,
            emptyAgentController: signedOutHarness.makeAgentController()
        )
        let shellState = try makeShellState(
            chatController: signedOutHarness.makeChatController(),
            agentController: populatedAgentController,
            settingsPresenter: signedInHarness.settingsPresenter
        )
        hostView(ContentView(appStore: shellState), runLoopDelay: 0.3)

        try? FileManager.default.removeItem(at: signedOutHarness.cacheRoot)
        try? FileManager.default.removeItem(at: signedInHarness.cacheRoot)
    }
}

@MainActor
private final class OverrideRootFactory: NativeChatRootOverrideFactory {
    func makeRootContent(modelContext _: ModelContext) -> AnyView? {
        AnyView(Text("Override Root"))
    }
}

@MainActor
private func hostBackendChatSurfaces(for chatController: BackendChatController) {
    hostView(
        BackendConversationTopBarSection(
            viewModel: chatController,
            onOpenSelector: {},
            onStartNewConversation: {}
        )
    )
    hostView(
        BackendChatEmptyState(
            viewModel: chatController,
            openSettings: {}
        )
    )
    hostView(
        BackendChatMessageList(
            viewModel: chatController,
            assistantBubbleMaxWidth: 520,
            streamingThinkingExpanded: Binding.constant(true),
            openSettings: {}
        )
    )
    hostView(
        BackendChatSelectorSheet(
            proModeEnabled: .constant(true),
            flexModeEnabled: .constant(true),
            reasoningEffort: .constant(.high),
            onDone: {}
        )
    )
    hostView(BackendChatView(viewModel: chatController, openSettings: {}))
}

@MainActor
private func hostBackendAgentSurfaces(
    _ agentController: BackendAgentController,
    emptyAgentController: BackendAgentController
) {
    hostView(
        BackendConversationTopBarSection(
            viewModel: agentController,
            onOpenSelector: {},
            onStartNewConversation: {}
        )
    )
    hostView(
        BackendAgentMessageList(
            viewModel: agentController,
            assistantBubbleMaxWidth: 520,
            liveSummaryExpanded: Binding.constant(true),
            streamingThinkingExpanded: Binding.constant(nil),
            expandedTraceMessageIDs: Binding.constant([agentController.messages[0].id]),
            openSettings: {}
        )
    )
    hostView(
        BackendAgentEmptyState(
            viewModel: emptyAgentController,
            openSettings: {}
        )
    )
    hostView(
        BackendAgentSelectorSheet(
            flexModeEnabled: .constant(true),
            leaderReasoningEffort: .constant(.high),
            workerReasoningEffort: .constant(.medium),
            onDone: {}
        )
    )
    hostView(
        BackendAgentSelectorOverlay(
            viewModel: agentController,
            selectedTheme: AppTheme.light,
            onDismiss: {}
        )
    )
    hostView(BackendAgentView(viewModel: agentController, openSettings: {}))
}

@MainActor
private func makeShellState(
    chatController: BackendChatController,
    agentController: BackendAgentController,
    settingsPresenter: SettingsPresenter
) throws -> NativeChatShellState {
    try NativeChatShellState(
        chatController: chatController,
        agentController: agentController,
        settingsPresenter: settingsPresenter,
        historyPresenter: HistoryPresenter(
            loadConversations: { [] },
            selectConversation: { _, _ in }
        ),
        selectedTab: 0,
        isUITestPreviewMode: true,
        uiTestPreviewItem: FilePreviewItem(
            url: makeSnapshotPDFFile(),
            kind: .generatedPDF,
            displayName: "PDF",
            viewerFilename: "report.pdf"
        )
    )
}
