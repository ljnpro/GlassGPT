import ChatPersistenceSwiftData
import NativeChatComposition
import SwiftUI
import Foundation
import SwiftData

public typealias NativeChatRootView = NativeChatComposition.NativeChatRootView

public enum NativeChatPersistence {
    public static let shared: ModelContainer = ChatPersistenceSwiftData.NativeChatPersistence.makeSharedContainer(
        bundleIdentifier: Bundle.main.bundleIdentifier
    )
}
