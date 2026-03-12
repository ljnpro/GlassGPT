import SwiftUI
import UIKit

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    var onRegenerate: (() -> Void)?

    // Live tool call state (passed from ChatView during streaming)
    var activeToolCalls: [ToolCallInfo] = []
    var liveCitations: [URLCitation] = []

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

                // File attachments (user messages)
                if message.role == .user && !message.fileAttachments.isEmpty {
                    FileAttachmentsRow(attachments: message.fileAttachments)
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

                // Active tool call indicators (during streaming)
                if message.role == .assistant {
                    ForEach(activeToolCalls) { toolCall in
                        switch toolCall.type {
                        case .webSearch:
                            if toolCall.status != .completed {
                                WebSearchIndicator()
                            }
                        case .codeInterpreter:
                            if toolCall.status != .completed {
                                CodeInterpreterIndicator()
                            }
                        }
                    }
                }

                // Completed tool call results (persisted in message)
                if message.role == .assistant {
                    let codeInterpreterCalls = message.toolCalls.filter { $0.type == .codeInterpreter }
                    ForEach(codeInterpreterCalls) { toolCall in
                        CodeInterpreterResultView(toolCall: toolCall)
                    }
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

                // Citations (from web search)
                if message.role == .assistant {
                    let allCitations = message.annotations.isEmpty ? liveCitations : message.annotations
                    CitationLinksView(citations: allCitations)
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
        VStack(alignment: .leading) {
            MarkdownContentView(text: message.content)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
        .compositingGroup()
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
            assistantPreview
        }
    }

    /// Lightweight, pure-SwiftUI preview for the context menu.
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
