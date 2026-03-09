/**
 * Polyfills for React Native production builds.
 *
 * - ReadableStream: Required for streaming fetch responses (SSE).
 *   Hermes in dev mode may have partial support, but production builds
 *   often lack it entirely.
 * - TextDecoder/TextEncoder: Required for decoding streamed Uint8Array chunks.
 *   Some older Hermes versions don't include these.
 */

import { Platform } from "react-native";

if (Platform.OS !== "web") {
  // Polyfill ReadableStream if not available
  if (typeof globalThis.ReadableStream === "undefined") {
    try {
      const webStreams = require("web-streams-polyfill/ponyfill");
      globalThis.ReadableStream = webStreams.ReadableStream;
      globalThis.WritableStream = webStreams.WritableStream;
      globalThis.TransformStream = webStreams.TransformStream;
    } catch {
      // Silently ignore if polyfill is not available
    }
  }

  // Polyfill TextDecoder/TextEncoder if not available
  if (typeof globalThis.TextDecoder === "undefined") {
    try {
      const encoding = require("text-encoding");
      globalThis.TextDecoder = encoding.TextDecoder;
      globalThis.TextEncoder = encoding.TextEncoder;
    } catch {
      // Silently ignore if polyfill is not available
    }
  }
}
