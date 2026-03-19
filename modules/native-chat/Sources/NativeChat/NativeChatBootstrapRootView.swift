import SwiftUI
import SwiftData

/// Entry-point view that initializes the SwiftData model container and presents the native chat root.
///
/// If the persistence bootstrap fails, displays an unavailable content view with the error description.
public struct NativeChatBootstrapRootView: View {
    let bootstrap: NativeChatPersistenceBootstrap
    let rootOverrideFactory: NativeChatRootOverrideFactory?

    /// Creates a bootstrap root view with the given persistence bootstrap and optional override factory.
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
