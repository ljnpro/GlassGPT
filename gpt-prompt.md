# Task: Complete Rewrite of React Native Chat App

You are rewriting a React Native (Expo SDK 54) mobile chat app that serves as a premium ChatGPT frontend. The app must feel like a first-party Apple iOS app with iOS 26 Liquid Glass design language.

## Key Requirements:
1. **Apple-style minimal, fluid design** - Clean, spacious, with subtle glass effects
2. **Model switching works** - GPT-5.4 (none/low/medium/high/xhigh) and GPT-5.4 Pro (medium/high/xhigh), default GPT-5.4 Pro xhigh
3. **Reasoning effort switching works** - Must work even without an active conversation
4. **API key input works** - Users can enter, validate, save their OpenAI API key
5. **Streaming chat** - Real-time token streaming with thinking/reasoning display
6. **Multimodal** - Image attachment support via expo-image-picker
7. **LaTeX rendering** - Math formulas rendered properly
8. **Markdown rendering** - Code blocks, tables, lists, bold, italic, links
9. **Conversation management** - History, search, delete

## Tech Stack:
- Expo SDK 54, React Native 0.81, React 19
- NativeWind v4 (Tailwind CSS), TypeScript
- expo-glass-effect (GlassView for iOS 26 native Liquid Glass)
- expo-blur (BlurView fallback)
- expo-image, expo-image-picker, expo-haptics
- expo-clipboard, expo-secure-store
- AsyncStorage for persistence
- MaterialIcons from @expo/vector-icons

## CRITICAL BUGS TO FIX:
1. Model selector: `handleModelChange` and `handleEffortChange` only dispatch when `activeConversation` exists. When there's no active conversation (fresh app), clicking the model selector opens the modal but selecting a model/effort does nothing because the dispatch is guarded by `if (activeConversation)`.
2. The chat store needs `pendingModel`/`pendingEffort` state for when no conversation is active yet.
3. API key TextInput may have focus/interaction issues on web.

## Files to Generate:

### 1. lib/types.ts
Keep the existing types but ensure they're correct.

### 2. lib/chat-store.tsx
- Add `pendingModel` and `pendingEffort` to state
- Add `currentModel`, `currentEffort`, `setCurrentModel`, `setCurrentEffort` to context
- These should read from: activeConversation > pending > settings defaults
- `setCurrentModel`/`setCurrentEffort` should update active conversation if exists, or set pending if not

### 3. lib/openai-service.ts
- Keep streaming implementation
- Ensure proper SSE parsing
- Handle reasoning_content delta

### 4. lib/secure-storage.ts
- Keep as is (SecureStore + web localStorage fallback)

### 5. components/glass-card.tsx
- Try expo-glass-effect GlassView on iOS 26
- Fallback to BlurView on native
- Fallback to CSS backdrop-filter on web
- Must look premium with subtle borders and shadows

### 6. components/model-selector.tsx
- Top bar dropdown showing current model + effort badge
- Tapping opens a clean modal/sheet
- Model chips: GPT-5.4, GPT-5.4 Pro
- Effort chips: show only valid efforts for selected model
- Must call `setCurrentModel`/`setCurrentEffort` from store (NOT dispatch directly)
- Apple-style segmented control look

### 7. components/chat-input.tsx
- Clean rounded input bar at bottom
- Image picker button (left), text input (center), send button (right)
- Stop button when streaming
- Image preview row above input when images attached
- Must work on web (TextInput focus)

### 8. components/message-bubble.tsx
- User messages: right-aligned, primary color bubble
- Assistant messages: left-aligned, glass card with markdown rendering
- Reasoning section: collapsible "Thinking..." section
- Long press to copy
- Model/effort tag below assistant messages

### 9. components/markdown-renderer.tsx
- Parse markdown blocks: headings, code, blockquotes, lists, tables, images, LaTeX
- Inline: bold, italic, code, links, inline LaTeX
- Code blocks with language label and copy button
- LaTeX: use unicode symbol replacement for display (no WebView needed)

### 10. app/(tabs)/index.tsx - Chat Screen
- Top: model selector + new chat button
- Middle: message list (FlatList)
- Bottom: chat input
- Empty state with welcome message
- KeyboardAvoidingView

### 11. app/(tabs)/conversations.tsx - History Screen
- Search bar at top
- List of conversations with title, preview, time, model badge
- Tap to open, long press to delete

### 12. app/(tabs)/settings.tsx - Settings Screen
- API Key section: TextInput + show/hide + save/validate + remove
- Default model selection
- Default reasoning effort selection
- Clear all conversations
- About section

### 13. app/(tabs)/_layout.tsx - Tab Layout
- 3 tabs: Chat, History, Settings
- MaterialIcons: chat-bubble, history, settings
- Clean tab bar styling

## Design Guidelines:
- Colors: iOS system colors (007AFF blue, F2F2F7 background, etc.)
- Typography: System font, bold headings, clean hierarchy
- Spacing: Generous padding, 16px horizontal margins
- Cards: Subtle glass effect with thin borders
- Interactions: Haptic feedback on taps
- The app should feel spacious, not cramped
- Use StyleSheet.create for all styles (no inline objects)
- Never use className on Pressable (use style prop)

Please generate the complete code for each file. Output each file with its path as a header.
