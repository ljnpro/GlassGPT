import ChatPersistenceCore
import ChatUIComponents
import GeneratedFilesCore
import NativeChatUI
import SwiftUI

/// Root tab view that composes the Chat, History, and Settings tabs.
package struct ContentView: View {
    /// The shared application store driving all tab content.
    @Bindable var appStore: NativeChatAppStore

    /// Creates the content view backed by the given app store.
    package init(appStore: NativeChatAppStore) {
        self.appStore = appStore
    }

    /// The root tab layout for chat, history, settings, and UI-test preview presentation.
    package var body: some View {
        @Bindable var settingsDefaults = appStore.settingsPresenter.defaults

        TabView(selection: selectedTabBinding) {
            Tab(String(localized: "Chat"), systemImage: "bubble.left.and.bubble.right.fill", value: 0) {
                ChatView(viewModel: appStore.chatController)
            }
            .accessibilityIdentifier("tab.chat")

            Tab(String(localized: "History"), systemImage: "clock.fill", value: 1) {
                NativeChatUI.HistoryView(store: appStore.historyPresenter)
            }
            .accessibilityIdentifier("tab.history")

            Tab(String(localized: "Settings"), systemImage: "gearshape.fill", value: 2) {
                NativeChatUI.SettingsView(viewModel: appStore.settingsPresenter)
            }
            .accessibilityIdentifier("tab.settings")
        }
        .environment(\.hapticsEnabled, settingsDefaults.hapticEnabled)
        .onOpenURL { url in
            appStore.router.handleURL(url)
        }
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
