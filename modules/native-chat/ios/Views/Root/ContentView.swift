import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var chatViewModel: ChatViewModel?
    @State private var settingsViewModel: SettingsViewModel?
    @State private var uiTestScenario: UITestScenario?
    @State private var uiTestPreviewItem: FilePreviewItem?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: 0) {
                if let vm = chatViewModel {
                    ChatView(viewModel: vm)
                } else {
                    ProgressView()
                }
            }

            Tab("History", systemImage: "clock.fill", value: 1) {
                HistoryView(
                    onSelectConversation: { conversation in
                        chatViewModel?.loadConversation(conversation)
                        selectedTab = 0
                    },
                    onDeleteConversation: { deletedConversation in
                        if chatViewModel?.currentConversation?.id == deletedConversation.id {
                            chatViewModel?.startNewChat()
                        }
                    },
                    onDeleteAllConversations: {
                        chatViewModel?.startNewChat()
                    }
                )
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                if let viewModel = settingsViewModel {
                    SettingsView(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
        .fullScreenCover(item: $uiTestPreviewItem, onDismiss: handleUITestPreviewDismiss) { previewItem in
            if uiTestScenario == .preview {
                FilePreviewSheet(
                    previewItem: previewItem,
                    onRequestDismiss: handleUITestPreviewDismiss
                )
            } else {
                Color.clear
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if chatViewModel == nil {
                if let bootstrap = UITestScenarioLoader.makeBootstrap(modelContext: modelContext) {
                    chatViewModel = bootstrap.chatViewModel
                    settingsViewModel = bootstrap.settingsViewModel
                    selectedTab = bootstrap.initialTab
                    uiTestScenario = bootstrap.scenario
                    if bootstrap.scenario == .preview {
                        uiTestPreviewItem = nil
                        Task { @MainActor in
                            await Task.yield()
                            uiTestPreviewItem = bootstrap.chatViewModel.filePreviewItem
                        }
                    }
                } else {
                    chatViewModel = ChatViewModel(modelContext: modelContext)
                    settingsViewModel = SettingsViewModel()
                }
            }
        }
    }

    private func handleUITestPreviewDismiss() {
        uiTestPreviewItem = nil
        chatViewModel?.filePreviewItem = nil
    }
}
