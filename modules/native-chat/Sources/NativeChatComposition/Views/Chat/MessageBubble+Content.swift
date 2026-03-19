import ChatPersistenceSwiftData
import ChatDomain
import NativeChatUI
import SwiftUI
import UIKit

extension MessageBubble {
    var displayedContent: String {
        if let liveContent, !liveContent.isEmpty {
            return liveContent
        }
        return message.content
    }

    var displayedThinking: String? {
        if let liveThinking, !liveThinking.isEmpty {
            return liveThinking
        }
        return message.thinking
    }

    var displayedToolCalls: [ToolCallInfo] {
        activeToolCalls.isEmpty ? message.toolCalls : activeToolCalls
    }

    var displayedCitations: [URLCitation] {
        liveCitations.isEmpty ? message.annotations : liveCitations
    }

    var displayedFilePathAnnotations: [FilePathAnnotation] {
        liveFilePathAnnotations.isEmpty ? message.filePathAnnotations : liveFilePathAnnotations
    }

    var isDisplayingLiveAssistantState: Bool {
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

            bubbleColumn
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

    private var bubbleColumn: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if message.role == .assistant, let thinking = displayedThinking, !thinking.isEmpty {
                ThinkingView(text: thinking, isLive: isDisplayingLiveAssistantState)
            }

            if message.role == .user && !message.fileAttachments.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(message.fileAttachments) { attachment in
                        FileAttachmentChip(attachment: attachment)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let imageData = message.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Attached image")
                    .accessibilityIdentifier("chat.message.image")
            }

            assistantToolIndicators
            assistantToolResults
            messageContent
            assistantCitations
            recoveryIndicator
        }
    }

    @ViewBuilder
    private var assistantToolIndicators: some View {
        if message.role == .assistant {
            if displayedToolCalls.contains(where: { $0.type == .webSearch && $0.status != .completed }) {
                WebSearchIndicator()
            }

            if displayedToolCalls.contains(where: { $0.type == .codeInterpreter && $0.status != .completed }) {
                CodeInterpreterIndicator()
            }

            if displayedToolCalls.contains(where: { $0.type == .fileSearch && $0.status != .completed }) {
                FileSearchIndicator()
            }
        }
    }

    @ViewBuilder
    private var assistantToolResults: some View {
        if message.role == .assistant {
            let codeInterpreterCalls = displayedToolCalls.filter { $0.type == .codeInterpreter }
            ForEach(codeInterpreterCalls) { toolCall in
                CodeInterpreterResultView(toolCall: toolCall)
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        let trimmedContent = displayedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            if message.role == .user {
                userBubble
            } else {
                assistantBubble
            }
        }
    }

    @ViewBuilder
    private var assistantCitations: some View {
        if message.role == .assistant {
            CitationLinksView(citations: displayedCitations)
        }
    }

    @ViewBuilder
    private var recoveryIndicator: some View {
        if message.role == .assistant, showsRecoveryIndicator {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Recovering…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recovering response")
            .accessibilityIdentifier("chat.recoveryIndicator")
        }
    }

    private var userBubble: some View {
        Text(displayedContent)
            .font(.body)
            .padding(12)
            .foregroundStyle(.white)
            .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("chat.user.bubble")
            .contextMenu {
                copyButton
                shareButton
            }
    }

    private var assistantBubble: some View {
        MarkdownContentView(
            text: displayedContent,
            filePathAnnotations: displayedFilePathAnnotations,
            onSandboxLinkTap: onSandboxLinkTap,
            surfaceStyle: .assistant(isLive: isDisplayingLiveAssistantState)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.assistant.surface")
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
}
