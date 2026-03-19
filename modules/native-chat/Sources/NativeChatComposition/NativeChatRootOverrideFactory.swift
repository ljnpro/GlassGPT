import SwiftData
import SwiftUI

/// Protocol allowing external modules to replace the entire root content of the native chat flow.
@MainActor
public protocol NativeChatRootOverrideFactory {
    /// Returns an override view to use instead of the standard chat root, or `nil` to use the default.
    func makeRootContent(modelContext: ModelContext) -> AnyView?
}
