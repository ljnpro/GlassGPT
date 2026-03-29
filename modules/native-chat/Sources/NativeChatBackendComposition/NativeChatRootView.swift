import ChatDomain
import GeneratedFilesCache
import NativeChatBackendCore
import NativeChatUI
import SwiftData
import SwiftUI
import UIKit

/// Top-level SwiftUI view that bootstraps the native chat composition root from the environment's model context.
public struct NativeChatRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @AppStorage("hasAcceptedDataSharing") private var hasAcceptedDataSharing = false
    @State private var appStore: NativeChatShellState?
    @State private var overrideContent: AnyView?
    private let rootOverrideFactory: (any NativeChatRootOverrideFactory)?

    /// Creates the root view with an optional override factory.
    public init(rootOverrideFactory: (any NativeChatRootOverrideFactory)? = nil) {
        self.rootOverrideFactory = rootOverrideFactory
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    /// The bootstrapped root content for the native chat feature.
    public var body: some View {
        rootContent
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                Task {
                    await GeneratedFileCacheManager().trimCachesForMemoryPressure()
                }
            }
    }

    private var rootContent: some View {
        Group {
            if let overrideContent {
                overrideContent
            } else if let appStore {
                ContentView(appStore: appStore)
            } else {
                ProgressView()
            }
        }
        .task {
            if overrideContent == nil, appStore == nil {
                if let rootOverrideFactory,
                   let content = rootOverrideFactory.makeRootContent(modelContext: modelContext) {
                    overrideContent = content
                    return
                }
                appStore = NativeChatCompositionRoot(modelContext: modelContext).makeAppStore()
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
        .fullScreenCover(isPresented: showConsentBinding) {
            DataSharingConsentView {
                hasAcceptedDataSharing = true
            }
        }
    }

    private var showConsentBinding: Binding<Bool> {
        Binding(
            get: { !hasAcceptedDataSharing && overrideContent == nil },
            set: { newValue in
                if !newValue {
                    hasAcceptedDataSharing = true
                }
            }
        )
    }
}
