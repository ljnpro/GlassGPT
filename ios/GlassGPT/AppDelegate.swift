import NativeChat
import SwiftUI
#if DEBUG
import NativeChatUITestSupport
#endif

@main
struct GlassGPTApp: App {
    private let persistenceBootstrap = NativeChatPersistence.makeBootstrap(
        bundleIdentifier: Bundle.main.bundleIdentifier
    )

    var body: some Scene {
        WindowGroup {
            rootView()
        }
    }

    @ViewBuilder
    private func rootView() -> some View {
        #if DEBUG
        NativeChatBootstrapRootView(
            bootstrap: persistenceBootstrap,
            rootOverrideFactory: NativeChatUITestRootOverrideFactory()
        )
        #else
        NativeChatBootstrapRootView(bootstrap: persistenceBootstrap)
        #endif
    }
}
