import { requireNativeModule } from "expo-modules-core";

// The native chat module - its primary purpose is the AppDelegate subscriber
// which replaces the React Native root with the SwiftUI app.
const NativeChat = requireNativeModule("NativeChat");

export default NativeChat;
