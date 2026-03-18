import SwiftUI
import SwiftData

public struct NativeChatBootstrapRootView: View {
    let bootstrap: NativeChatPersistenceBootstrap
    let rootOverrideFactory: NativeChatRootOverrideFactory?

    public init(
        bootstrap: NativeChatPersistenceBootstrap,
        rootOverrideFactory: NativeChatRootOverrideFactory? = nil
    ) {
        self.bootstrap = bootstrap
        self.rootOverrideFactory = rootOverrideFactory
    }

    public var body: some View {
        if let modelContainer = bootstrap.container {
            bootstrapContent(modelContainer: modelContainer)
        } else {
            ContentUnavailableView(
                "Storage Unavailable",
                systemImage: "externaldrive.badge.xmark",
                description: Text(
                    bootstrap.startupErrorDescription
                        ?? "Local storage could not be initialized."
                )
            )
            .padding()
        }
    }

    @ViewBuilder
    func bootstrapContent(modelContainer: ModelContainer) -> some View {
        if let rootOverrideFactory {
            NativeChatRootView(rootOverrideFactory: rootOverrideFactory)
                .modelContainer(modelContainer)
        } else {
            NativeChatRootView()
                .modelContainer(modelContainer)
        }
    }
}
