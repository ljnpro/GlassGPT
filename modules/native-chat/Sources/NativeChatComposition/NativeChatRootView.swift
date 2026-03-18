import ChatDomain
import NativeChatUI
import SwiftData
import SwiftUI

public struct NativeChatRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @State private var appStore: NativeChatAppStore?

    public init() {}

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    public var body: some View {
        Group {
            if let appStore {
                ContentView(appStore: appStore)
            } else {
                ProgressView()
            }
        }
        .task {
            if appStore == nil {
                appStore = NativeChatCompositionRoot(modelContext: modelContext).makeAppStore()
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}
