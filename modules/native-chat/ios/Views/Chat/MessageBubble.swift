import SwiftUI
import UIKit

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    var onRegenerate: (() -> Void)?

    @State private var showThinking = false

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Thinking toggle
                if message.role == .assistant, let thinking = message.thinking, !thinking.isEmpty {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            showThinking.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.caption2)
                            Text(showThinking ? "Hide Thinking" : "Show Thinking")
                                .font(.caption2)
                            Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if showThinking {
                        ThinkingView(text: thinking)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Image attachment
                if let imageData = message.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Message content - only show if non-empty
                let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedContent.isEmpty {
                    if message.role == .user {
                        userBubble
                    } else {
                        assistantBubble
                    }
                }

                // Incomplete message indicator
                if message.role == .assistant && !message.isComplete {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Recovering…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.85,
                   alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        Text(message.content)
            .font(.body)
            .padding(12)
            .foregroundStyle(.white)
            .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 20))
            .contextMenu {
                copyButton
                shareButton
            }
    }

    // MARK: - Assistant Bubble

    private var assistantBubble: some View {
        // The bubble content with MarkdownContentView (contains WKWebViews for
        // LaTeX and interactive glass Buttons inside CodeBlockView).
        //
        // Strategy:
        //  • .compositingGroup() flattens the entire bubble into a single
        //    rendered bitmap layer. This prevents WKWebView's CALayer from
        //    sitting above the system context-menu chrome.
        //  • .contentShape() ensures the entire rounded rect is the hit-test
        //    area for the context menu.
        //  • .contextMenu with an explicit `preview:` supplies a pure-SwiftUI
        //    snapshot so the system never needs to rasterize WKWebViews.
        //
        // Because .contextMenu is on the outer container (not on any child
        // Button), the system anchors the menu to the whole bubble — not to
        // the code-block Copy button. The code-block Copy button still
        // responds to normal taps because .contextMenu only activates on
        // long-press.
        VStack(alignment: .leading) {
            MarkdownContentView(text: message.content)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
        // Flatten all sublayers (WKWebView, Buttons) into one composited
        // bitmap so nothing can poke above the context-menu overlay.
        .compositingGroup()
        // Make the entire bubble the hit-test target for context menu.
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
        .contextMenu {
            copyButton

            if let onRegenerate {
                Button {
                    onRegenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.trianglehead.2.counterclockwise")
                }
            }

            shareButton
        } preview: {
            // Pure-SwiftUI preview — no WKWebView, no interactive buttons.
            // This avoids the WKWebView snapshot glitch entirely.
            assistantPreview
        }
    }

    /// Lightweight, pure-SwiftUI preview for the context menu.
    /// Shows a plain-text rendition of the message content.
    private var assistantPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.content.prefix(1500))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if message.content.count > 1500 {
                Text("…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        }
    }

    // MARK: - Context Menu Items

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.content
            HapticService.shared.impact(.light)
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }
    }

    private var shareButton: some View {
        ShareLink(item: message.content) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}
