import NativeChat
import SwiftUI

@main
struct GlassGPTApp: App {
    private let persistenceBootstrap = NativeChatPersistence.bootstrap

    var body: some Scene {
        WindowGroup {
            if let modelContainer = persistenceBootstrap.container {
                NativeChatRootView()
                    .modelContainer(modelContainer)
            } else {
                ContentUnavailableView(
                    "Storage Unavailable",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text(
                        persistenceBootstrap.startupErrorDescription
                            ?? "Local storage could not be initialized."
                    )
                )
                .padding()
            }
        }
    }
}
