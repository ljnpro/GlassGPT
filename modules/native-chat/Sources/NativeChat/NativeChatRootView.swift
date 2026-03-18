import ChatPersistenceSwiftData
import NativeChatComposition
import SwiftUI
import Foundation
import SwiftData

public typealias NativeChatRootView = NativeChatComposition.NativeChatRootView

@MainActor
public enum NativeChatPersistence {
    public static let bootstrap: ChatPersistenceSwiftData.NativeChatPersistenceBootstrap =
        ChatPersistenceSwiftData.NativeChatPersistence.makeSharedBootstrap(
            bundleIdentifier: Bundle.main.bundleIdentifier
        )

    public static var shared: ModelContainer? {
        bootstrap.container
    }

    public static var startupErrorDescription: String? {
        bootstrap.startupErrorDescription
    }

    public static var didRecoverPersistentStore: Bool {
        bootstrap.didRecoverPersistentStore
    }
}
