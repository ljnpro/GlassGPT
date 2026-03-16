import NativeChat
import SwiftData
import SwiftUI

@main
struct GlassGPTApp: App {
    var body: some Scene {
        WindowGroup {
            NativeChatRootView()
                .modelContainer(NativeChatPersistence.shared)
        }
    }
}
