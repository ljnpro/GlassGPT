import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appStore: NativeChatAppStore?

    var body: some View {
        TabView(selection: selectedTabBinding) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: 0) {
                if let appStore {
                    let vm = appStore.chatScreenStore
                    ChatView(viewModel: vm)
                } else {
                    ProgressView()
                }
            }

            Tab("History", systemImage: "clock.fill", value: 1) {
                if let appStore {
                    HistoryView(store: appStore.historyScreenStore)
                } else {
                    ProgressView()
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                if let appStore {
                    let viewModel = appStore.settingsScreenStore
                    SettingsView(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
        .fullScreenCover(item: uiTestPreviewItemBinding, onDismiss: handleUITestPreviewDismiss) { previewItem in
            if appStore?.uiTestScenario == .preview {
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
            if appStore == nil {
                appStore = NativeChatAppStore(modelContext: modelContext)
            }
        }
    }

    private func handleUITestPreviewDismiss() {
        appStore?.handleUITestPreviewDismiss()
    }

    private var selectedTabBinding: Binding<Int> {
        Binding(
            get: { appStore?.selectedTab ?? 0 },
            set: { appStore?.selectedTab = $0 }
        )
    }

    private var uiTestPreviewItemBinding: Binding<FilePreviewItem?> {
        Binding(
            get: { appStore?.uiTestPreviewItem },
            set: { appStore?.uiTestPreviewItem = $0 }
        )
    }
}
