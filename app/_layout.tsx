// Minimal React Native shell - SwiftUI takes over the root view on iOS
// This file exists only to satisfy Expo Router's entry point requirement

import { Slot } from "expo-router";

export default function RootLayout() {
  return <Slot />;
}
