import SwiftData
import SwiftUI

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

    /// The bootstrapped root content or a storage-unavailable fallback.
    public var body: some View {
        rootContent
    }

    @ViewBuilder
    private var rootContent: some View {
        if let modelContainer = bootstrap.container {
            bootstrapContent(modelContainer: modelContainer)
        } else {
            ContentUnavailableView(
                String(localized: "Storage Unavailable"),
                systemImage: "externaldrive.badge.xmark",
                description: Text(
                    bootstrap.startupErrorDescription
                        ?? String(localized: "Local storage could not be initialized.")
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
