import ChatPersistenceCore
import ChatPresentation
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
                    openSettings: { appStore.selectTab(3) },
                    onSandboxLinkTap: appStore.handleSandboxLinkTap
                )
            }
            .accessibilityIdentifier("glassgpt.tab.chat")

            Tab(String(localized: "Agent"), systemImage: "person.3.fill", value: 1) {
                BackendAgentView(
                    viewModel: appStore.agentController,
                    openSettings: { appStore.selectTab(3) },
                    onSandboxLinkTap: appStore.handleSandboxLinkTap
                )
            }
            .accessibilityIdentifier("glassgpt.tab.agent")

            Tab(String(localized: "History"), systemImage: "clock.fill", value: 2) {
                NativeChatUI.HistoryView(store: appStore.historyPresenter)
            }
            .accessibilityIdentifier("glassgpt.tab.history")

            Tab(String(localized: "Settings"), systemImage: "gearshape.fill", value: 3) {
                NativeChatUI.SettingsView(viewModel: appStore.settingsPresenter)
            }
            .accessibilityIdentifier("glassgpt.tab.settings")
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
        .fullScreenCover(item: generatedFilePreviewItemBinding, onDismiss: appStore.dismissGeneratedFilePreview) { previewItem in
            FilePreviewSheet(
                previewItem: previewItem,
                onRequestDismiss: appStore.dismissGeneratedFilePreview
            )
        }
        .sheet(item: sharedGeneratedFileItemBinding, onDismiss: appStore.dismissGeneratedFileShareSheet) { item in
            ActivityViewController(activityItems: [item.url])
        }
        .alert(String(localized: "Download Failed"), isPresented: generatedFileDownloadErrorPresentedBinding) {
            Button(String(localized: "OK"), role: .cancel) {
                appStore.clearGeneratedFileDownloadError()
            }
        } message: {
            Text(
                appStore.filePreviewStore.fileDownloadError
                    ?? String(localized: "Unable to download this file.")
            )
        }
        .overlay(alignment: .bottom) {
            if appStore.filePreviewStore.isDownloadingFile {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Downloading file…"))
                        .font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 24)
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

    private var generatedFilePreviewItemBinding: Binding<FilePreviewItem?> {
        Binding(
            get: { appStore.filePreviewStore.filePreviewItem },
            set: { appStore.filePreviewStore.filePreviewItem = $0 }
        )
    }

    private var sharedGeneratedFileItemBinding: Binding<SharedGeneratedFileItem?> {
        Binding(
            get: { appStore.filePreviewStore.sharedGeneratedFileItem },
            set: { appStore.filePreviewStore.sharedGeneratedFileItem = $0 }
        )
    }

    private var generatedFileDownloadErrorPresentedBinding: Binding<Bool> {
        Binding(
            get: { appStore.filePreviewStore.fileDownloadError != nil },
            set: { newValue in
                if !newValue {
                    appStore.clearGeneratedFileDownloadError()
                }
            }
        )
    }
}
