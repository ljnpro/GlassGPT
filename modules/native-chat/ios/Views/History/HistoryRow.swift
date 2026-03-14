import SwiftUI

struct HistoryRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(modelDisplayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .glassEffect(.regular, in: Capsule())
            }
        }
        .padding(.vertical, 6)
    }

    private var lastMessagePreview: String {
        let sorted = conversation.messages.sorted { $0.createdAt < $1.createdAt }
        guard let lastMessage = sorted.last else {
            return "No messages"
        }

        let trimmedContent = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return trimmedContent.prefix(100).description
        }

        if lastMessage.role == .assistant && !lastMessage.isComplete {
            if let thinking = lastMessage.thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thinking.isEmpty {
                return thinking.prefix(100).description
            }

            return "Generating..."
        }

        return "No messages"
    }

    private var modelDisplayName: String {
        ModelType(rawValue: conversation.model)?.displayName ?? conversation.model
    }
}
