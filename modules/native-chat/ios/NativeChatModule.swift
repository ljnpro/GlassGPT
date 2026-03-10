import ExpoModulesCore

public class NativeChatModule: Module {
    public func definition() -> ModuleDefinition {
        Name("NativeChat")
        
        // This module's primary purpose is the AppDelegate subscriber
        // which replaces the React Native root with SwiftUI.
        // No JS-callable functions needed.
        Function("isNative") {
            return true
        }
    }
}
