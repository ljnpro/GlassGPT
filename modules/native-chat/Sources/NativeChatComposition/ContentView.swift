import ChatPersistenceCore
import ChatUIComponents
import GeneratedFilesCore
import NativeChatUI
import OpenAITransport
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appStore: NativeChatAppStore?

    var body: some View {
        TabView(selection: selectedTabBinding) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: 0) {
                if let appStore {
                    ChatView(viewModel: appStore.chatController)
                } else {
                    ProgressView()
                }
            }

            Tab("History", systemImage: "clock.fill", value: 1) {
                if let appStore {
                    NativeChatUI.HistoryView(store: appStore.historyPresenter)
                } else {
                    ProgressView()
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                if let appStore {
                    NativeChatUI.SettingsView(viewModel: appStore.settingsPresenter)
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
            HapticService.isEnabledProvider = { SettingsStore.shared.hapticEnabled }
            DefaultOpenAIConfigurationProvider.shared.configure(
                directOpenAIBaseURL: {
                    DefaultOpenAIConfigurationProvider.defaultOpenAIBaseURL
                },
                cloudflareGatewayBaseURL: {
                    if let infoValue = Bundle.main.object(forInfoDictionaryKey: "CloudflareGatewayBaseURL") as? String,
                       !infoValue.isEmpty {
                        return infoValue
                    }

                    if let environmentValue = ProcessInfo.processInfo.environment["CLOUDFLARE_GATEWAY_BASE_URL"],
                       !environmentValue.isEmpty {
                        return environmentValue
                    }

                    return DefaultOpenAIConfigurationProvider.bundledCloudflareGatewayBaseURL
                },
                cloudflareAIGToken: {
                    if let infoValue = Bundle.main.object(forInfoDictionaryKey: "CloudflareAIGToken") as? String,
                       !infoValue.isEmpty {
                        return infoValue
                    }

                    if let environmentValue = ProcessInfo.processInfo.environment["CLOUDFLARE_AIG_TOKEN"],
                       !environmentValue.isEmpty {
                        return environmentValue
                    }

                    return DefaultOpenAIConfigurationProvider.bundledCloudflareAIGToken
                },
                useCloudflareGateway: {
                    SettingsStore.shared.cloudflareGatewayEnabled
                },
                setUseCloudflareGateway: { enabled in
                    SettingsStore.shared.cloudflareGatewayEnabled = enabled
                }
            )
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
