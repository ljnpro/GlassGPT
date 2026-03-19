import ChatPersistenceSwiftData
import Foundation
import NativeChatComposition
import SwiftData
import SwiftUI

/// Re-exported alias for the composition root view.
public typealias NativeChatRootView = NativeChatComposition.NativeChatRootView
/// Re-exported alias for the persistence bootstrap type.
public typealias NativeChatPersistenceBootstrap = ChatPersistenceSwiftData.NativeChatPersistenceBootstrap
/// Re-exported alias for the root override factory protocol.
public typealias NativeChatRootOverrideFactory = NativeChatComposition.NativeChatRootOverrideFactory

/// Namespace providing convenience factory methods for persistence bootstrapping.
public enum NativeChatPersistence {
    /// Creates a shared persistence bootstrap configured for the given bundle identifier.
    public static func makeBootstrap(bundleIdentifier: String?) -> NativeChatPersistenceBootstrap {
        ChatPersistenceSwiftData.NativeChatPersistence.makeSharedBootstrap(
            bundleIdentifier: bundleIdentifier
        )
    }
}
