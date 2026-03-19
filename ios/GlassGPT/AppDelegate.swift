import ChatPersistenceCore
import MetricKit
import NativeChat
import SwiftUI
#if DEBUG
import NativeChatUI
import NativeChatUITestSupport
#endif

@main
struct GlassGPTApp: App {
    private let persistenceBootstrap = NativeChatPersistence.makeBootstrap(
        bundleIdentifier: Bundle.main.bundleIdentifier
    )
    private let launchStart: CFAbsoluteTime
    private let metricKitSubscriber = MetricKitSubscriber()

    init() {
        launchStart = CFAbsoluteTimeGetCurrent()
        MXMetricManager.shared.add(metricKitSubscriber)
    }

    var body: some Scene {
        WindowGroup {
            rootView()
                .onAppear {
                    let elapsed = CFAbsoluteTimeGetCurrent() - launchStart
                    Loggers.diagnostics.info("[Launch] Root view appeared in \(String(format: "%.1f", elapsed * 1000)) ms")
                    #if DEBUG
                    LaunchTimingStore.shared.launchDuration = elapsed
                    #endif
                }
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
