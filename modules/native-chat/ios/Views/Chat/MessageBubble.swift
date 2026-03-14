import SwiftUI
import UIKit

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    var onRegenerate: (() -> Void)?

    // Live assistant state overrides (passed from ChatView during streaming/recovery)
    var liveContent: String?
    var liveThinking: String?
    var activeToolCalls: [ToolCallInfo] = []
    var liveCitations: [URLCitation] = []
    var liveFilePathAnnotations: [FilePathAnnotation] = []
    var showsRecoveryIndicator: Bool = false

    // File preview handler
    var onSandboxLinkTap: ((String, FilePathAnnotation?) -> Void)?

    private var displayedContent: String {
        if let liveContent, !liveContent.isEmpty {
            return liveContent
        }
        return message.content
    }

    private var displayedThinking: String? {
        if let liveThinking, !liveThinking.isEmpty {
            return liveThinking
        }
        return message.thinking
    }

    private var displayedToolCalls: [ToolCallInfo] {
        activeToolCalls.isEmpty ? message.toolCalls : activeToolCalls
    }

    private var displayedCitations: [URLCitation] {
        liveCitations.isEmpty ? message.annotations : liveCitations
    }

    private var displayedFilePathAnnotations: [FilePathAnnotation] {
        liveFilePathAnnotations.isEmpty ? message.filePathAnnotations : liveFilePathAnnotations
    }

    private var isDisplayingLiveAssistantState: Bool {
        message.role == .assistant && (
            (liveContent?.isEmpty == false) ||
            (liveThinking?.isEmpty == false) ||
            !activeToolCalls.isEmpty ||
            !liveCitations.isEmpty ||
            !liveFilePathAnnotations.isEmpty ||
            showsRecoveryIndicator
        )
    }

    private var bubbleMaxWidth: CGFloat {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return 680
        default:
            return 520
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Thinking/reasoning (collapsible, completed — starts collapsed)
                if message.role == .assistant, let thinking = displayedThinking, !thinking.isEmpty {
                    ThinkingView(text: thinking, isLive: isDisplayingLiveAssistantState)
                }

                // File attachments (user messages) — aligned right
                if message.role == .user && !message.fileAttachments.isEmpty {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(message.fileAttachments) { attachment in
                            FileAttachmentChip(attachment: attachment)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
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

                // Active tool call indicators (during streaming) — deduplicated
                if message.role == .assistant {
                    // Only show ONE web search indicator, regardless of how many web search calls are active
                    let hasActiveWebSearch = displayedToolCalls.contains { $0.type == .webSearch && $0.status != .completed }
                    if hasActiveWebSearch {
                        WebSearchIndicator()
                    }

                    // Only show ONE code interpreter indicator
                    let hasActiveCodeInterpreter = displayedToolCalls.contains { $0.type == .codeInterpreter && $0.status != .completed }
                    if hasActiveCodeInterpreter {
                        CodeInterpreterIndicator()
                    }

                    // Only show ONE file search indicator
                    let hasActiveFileSearch = displayedToolCalls.contains { $0.type == .fileSearch && $0.status != .completed }
                    if hasActiveFileSearch {
                        FileSearchIndicator()
                    }
                }

                // Completed tool call results (persisted in message)
                if message.role == .assistant {
                    let codeInterpreterCalls = displayedToolCalls.filter { $0.type == .codeInterpreter }
                    ForEach(codeInterpreterCalls) { toolCall in
                        CodeInterpreterResultView(toolCall: toolCall)
                    }
                }

                // Message content - only show if non-empty
                let trimmedContent = displayedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedContent.isEmpty {
                    if message.role == .user {
                        userBubble
                    } else {
                        assistantBubble
                    }
                }

                // Citations (from web search)
                if message.role == .assistant {
                    CitationLinksView(citations: displayedCitations)
                }

                // Incomplete message indicator
                if message.role == .assistant && showsRecoveryIndicator {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Recovering…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(
                maxWidth: bubbleMaxWidth,
                alignment: message.role == .user ? .trailing : .leading
            )

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        Text(displayedContent)
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
            MarkdownContentView(
                text: displayedContent,
                filePathAnnotations: displayedFilePathAnnotations,
                onSandboxLinkTap: onSandboxLinkTap
            )
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
            Text(displayedContent.prefix(1500))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            if displayedContent.count > 1500 {
                Text("…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        }
    }

    // MARK: - Context Menu Items

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = displayedContent
            HapticService.shared.impact(.light)
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }
    }

    private var shareButton: some View {
        ShareLink(item: displayedContent) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}
