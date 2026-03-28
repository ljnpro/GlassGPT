import ChatPersistenceCore
import ChatUIComponents
import GeneratedFilesCore
import NativeChatBackendCore
import NativeChatUI
import SwiftUI

/// Root tab view that composes the Chat, Agent, History, and Settings tabs.
package struct ContentView: View {
    /// The shared application store driving all tab content.
    @Bindable var appStore: NativeChatShellState

    /// Creates the content view backed by the given app store.
    package init(appStore: NativeChatShellState) {
        self.appStore = appStore
    }

    /// The root tab layout for chat, agent, history, settings, and UI-test preview presentation.
    package var body: some View {
        @Bindable var settingsDefaults = appStore.settingsPresenter.defaults

        TabView(selection: selectedTabBinding) {
            Tab(String(localized: "Chat"), systemImage: "bubble.left.and.bubble.right.fill", value: 0) {
                BackendChatView(
                    viewModel: appStore.chatController,
                    openSettings: { appStore.selectTab(3) }
                )
            }
            .accessibilityIdentifier("tab.chat")

            Tab(String(localized: "Agent"), systemImage: "person.3.fill", value: 1) {
                BackendAgentView(
                    viewModel: appStore.agentController,
                    openSettings: { appStore.selectTab(3) }
                )
            }
            .accessibilityIdentifier("tab.agent")

            Tab(String(localized: "History"), systemImage: "clock.fill", value: 2) {
                NativeChatUI.HistoryView(store: appStore.historyPresenter)
            }
            .accessibilityIdentifier("tab.history")

            Tab(String(localized: "Settings"), systemImage: "gearshape.fill", value: 3) {
                NativeChatUI.SettingsView(viewModel: appStore.settingsPresenter)
            }
            .accessibilityIdentifier("tab.settings")
        }
        .environment(\.hapticsEnabled, settingsDefaults.hapticEnabled)
        .onOpenURL { url in
            appStore.handleOpenURL(url)
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
            set: { appStore.selectTab($0) }
        )
    }

    private var uiTestPreviewItemBinding: Binding<FilePreviewItem?> {
        Binding(
            get: { appStore.uiTestPreviewItem },
            set: { appStore.uiTestPreviewItem = $0 }
        )
    }
}
