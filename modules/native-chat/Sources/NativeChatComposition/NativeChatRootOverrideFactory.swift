import SwiftData
import SwiftUI

@MainActor
public protocol NativeChatRootOverrideFactory {
    func makeRootContent(modelContext: ModelContext) -> AnyView?
}
