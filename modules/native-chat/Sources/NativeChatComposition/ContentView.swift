import ChatPersistenceCore
import ChatUIComponents
import GeneratedFilesCore
import NativeChatUI
import SwiftUI

package struct ContentView: View {
    @Bindable var appStore: NativeChatAppStore

    package init(appStore: NativeChatAppStore) {
        self.appStore = appStore
    }

    package var body: some View {
        TabView(selection: selectedTabBinding) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: 0) {
                ChatView(viewModel: appStore.chatController)
            }

            Tab("History", systemImage: "clock.fill", value: 1) {
                NativeChatUI.HistoryView(store: appStore.historyPresenter)
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                NativeChatUI.SettingsView(viewModel: appStore.settingsPresenter)
            }
        }
        .environment(\.hapticsEnabled, appStore.settingsPresenter.hapticEnabled)
        .tabBarMinimizeBehavior(.never)
        .fullScreenCover(item: uiTestPreviewItemBinding, onDismiss: handleUITestPreviewDismiss) { previewItem in
            if appStore.isUITestPreviewMode {
                FilePreviewSheet(
                    previewItem: previewItem,
                    onRequestDismiss: handleUITestPreviewDismiss
                )
            } else {
                Color.clear
                    .ignoresSafeArea()
            }
        }
    }

    private func handleUITestPreviewDismiss() {
        appStore.handleUITestPreviewDismiss()
    }

    private var selectedTabBinding: Binding<Int> {
        Binding(
            get: { appStore.selectedTab },
            set: { appStore.selectedTab = $0 }
        )
    }

    private var uiTestPreviewItemBinding: Binding<FilePreviewItem?> {
        Binding(
            get: { appStore.uiTestPreviewItem },
            set: { appStore.uiTestPreviewItem = $0 }
        )
    }
}
