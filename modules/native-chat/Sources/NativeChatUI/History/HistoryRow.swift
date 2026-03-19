import ChatPresentation
import ChatUIComponents
import SwiftUI

/// A single row in the conversation history list, showing the title, preview, timestamp, and model badge.
public struct HistoryRow: View {
    /// The conversation data to display.
    let conversation: HistoryConversationRow

    /// Creates a history row for the given conversation.
    public init(conversation: HistoryConversationRow) {
        self.conversation = conversation
    }

    /// The rendered row content for one conversation summary.
    public var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(conversation.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(conversation.modelDisplayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .singleSurfaceGlass(
                        cornerRadius: 999,
                        stableFillOpacity: 0.01,
                        borderWidth: 0.7,
                        darkBorderOpacity: 0.14,
                        lightBorderOpacity: 0.08
                    )
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.title), \(conversation.modelDisplayName)")
        .accessibilityHint(conversation.preview)
    }
}
