import ChatProjectionPersistence
import Foundation
import NativeChatBackendComposition
import SwiftData
import SwiftUI

/// Re-exported alias for the composition root view.
public typealias NativeChatRootView = NativeChatBackendComposition.NativeChatRootView
/// Re-exported alias for the persistence bootstrap type.
public typealias NativeChatPersistenceBootstrap = ChatProjectionPersistence.NativeChatPersistenceBootstrap
/// Re-exported alias for the root override factory protocol.
public typealias NativeChatRootOverrideFactory = NativeChatBackendComposition.NativeChatRootOverrideFactory

/// Namespace providing convenience factory methods for persistence bootstrapping.
public enum NativeChatPersistence {
    /// Creates a shared persistence bootstrap configured for the given bundle identifier.
    public static func makeBootstrap(bundleIdentifier: String?) -> NativeChatPersistenceBootstrap {
        ChatProjectionPersistence.NativeChatPersistence.makeSharedBootstrap(
            bundleIdentifier: bundleIdentifier
        )
    }
}
