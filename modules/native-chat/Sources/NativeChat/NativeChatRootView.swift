import ChatPersistenceSwiftData
import NativeChatComposition
import SwiftUI
import Foundation
import SwiftData

public typealias NativeChatRootView = NativeChatComposition.NativeChatRootView
public typealias NativeChatPersistenceBootstrap = ChatPersistenceSwiftData.NativeChatPersistenceBootstrap
public typealias NativeChatRootOverrideFactory = NativeChatComposition.NativeChatRootOverrideFactory

public enum NativeChatPersistence {
    public static func makeBootstrap(bundleIdentifier: String?) -> NativeChatPersistenceBootstrap {
        ChatPersistenceSwiftData.NativeChatPersistence.makeSharedBootstrap(
            bundleIdentifier: bundleIdentifier
        )
    }
}
