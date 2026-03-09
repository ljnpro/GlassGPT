# Liquid Glass Chat — Design Document

## Overview

A premium ChatGPT-like mobile frontend with iOS 26 Liquid Glass aesthetics. Users provide their own OpenAI API key to interact with GPT-5.4 and GPT-5.4-pro models. The app should feel better than the official ChatGPT app — cleaner, faster, more elegant.

## Screen List

### 1. Chat Screen (Main)
- Top bar: Model selector dropdown (GPT-5.4 / GPT-5.4-pro) + Reasoning effort selector + New chat button
- Message list: Alternating user/assistant bubbles with Liquid Glass effect on assistant messages
- Input area: Text input with send button, image attach button, expanding multiline
- Streaming response with typing indicator
- Supports: text, images (inline), code blocks with syntax highlighting, LaTeX formulas, markdown tables

### 2. Conversation List Screen (Sidebar/Tab)
- List of all past conversations with title preview and timestamp
- Swipe to delete
- Search bar at top
- New conversation button
- Glass-effect cards for each conversation

### 3. Settings Screen
- API Key input (stored securely via SecureStore, with localStorage fallback on web)
- Default model selection
- Default reasoning effort
- Theme toggle (light/dark/system)
- About section

## Primary Content and Functionality

### Chat Screen
- **Header**: Glass-effect top bar with model picker (dropdown) and reasoning effort picker
  - Model options: "GPT-5.4", "GPT-5.4 Pro"
  - Reasoning effort for GPT-5.4: none, low, medium, high, xhigh
  - Reasoning effort for GPT-5.4 Pro: medium, high, xhigh
  - Default: GPT-5.4 Pro + xhigh
- **Message List**: FlatList with inverted scroll
  - User messages: right-aligned, primary color bubble
  - Assistant messages: left-aligned, glass/surface bubble with markdown rendering
  - Image messages: inline image thumbnails, tappable for full view
  - Code blocks: syntax highlighted with copy button
  - LaTeX: rendered inline and block formulas
  - Thinking/reasoning: collapsible section showing model's reasoning process
- **Input Bar**: Fixed at bottom
  - Multi-line TextInput (auto-expanding up to 6 lines)
  - Send button (disabled when empty or loading)
  - Image picker button (camera roll)
  - Image preview thumbnails before sending
  - Stop generation button (when streaming)

### Conversation List
- Each item shows: conversation title (auto-generated from first message), last message preview, timestamp
- Pull to refresh
- Swipe-to-delete with haptic feedback
- Empty state with prompt to start new chat

### Settings
- API Key field with show/hide toggle
- Model and effort defaults
- Clear all conversations option
- App version info

## Key User Flows

### Flow 1: First Launch
1. App opens → Settings screen prompts for API key
2. User enters API key → Validated with a test request
3. Redirected to Chat screen → Ready to chat

### Flow 2: New Conversation
1. User taps "New Chat" or starts typing in empty chat
2. Select model/effort from top bar dropdowns
3. Type message → Tap send
4. Streaming response appears with typing animation
5. Conversation auto-saved with generated title

### Flow 3: Send Image
1. Tap image button in input bar
2. Select image from library
3. Image thumbnail appears in input area
4. Type optional text → Send
5. Model processes image and responds

### Flow 4: Switch Model Mid-Conversation
1. Tap model selector in top bar
2. Choose different model from dropdown
3. Adjust reasoning effort if needed
4. Next message uses new model settings

### Flow 5: View Past Conversations
1. Navigate to Conversations tab
2. Scroll through list or search
3. Tap conversation to resume
4. Continue chatting

## Color Choices

### Light Mode
- **Background**: #F2F2F7 (iOS system grouped background)
- **Surface**: #FFFFFF (cards, message bubbles)
- **Primary**: #007AFF (iOS blue - send button, links, active elements)
- **Foreground**: #000000 (primary text)
- **Muted**: #8E8E93 (secondary text, timestamps)
- **Border**: #C6C6C8 (separators)
- **User Bubble**: #007AFF (blue with white text)
- **Assistant Bubble**: rgba(255,255,255,0.85) (glass effect)
- **Success**: #34C759
- **Error**: #FF3B30

### Dark Mode
- **Background**: #000000 (true black for OLED)
- **Surface**: #1C1C1E (elevated surface)
- **Primary**: #0A84FF (iOS blue dark)
- **Foreground**: #FFFFFF
- **Muted**: #8E8E93
- **Border**: #38383A
- **User Bubble**: #0A84FF
- **Assistant Bubble**: rgba(28,28,30,0.85) (glass effect)
- **Success**: #30D158
- **Error**: #FF453A

## Typography
- System font (San Francisco on iOS, Roboto on Android)
- Message text: 16px
- Code: 14px monospace
- Timestamps: 12px muted
- Headers in markdown: scaled appropriately

## Animations
- Message appear: fade in + slide up (200ms)
- Streaming text: character-by-character with cursor blink
- Model selector: smooth dropdown with glass backdrop
- Tab transitions: cross-fade (250ms)
- Button press: scale 0.97 + haptic light

## Liquid Glass Implementation
- Use `expo-glass-effect` GlassView on iOS 26+ for:
  - Top navigation bar
  - Model selector dropdown
  - Assistant message bubbles (subtle)
- Fallback to `expo-blur` BlurView on older iOS / Android
- On web: CSS backdrop-filter with fallback to solid colors
