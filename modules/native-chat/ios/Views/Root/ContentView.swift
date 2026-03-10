import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var chatViewModel: ChatViewModel?

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
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onAppear {
            if chatViewModel == nil {
                chatViewModel = ChatViewModel(modelContext: modelContext)
            }
        }
    }
}
