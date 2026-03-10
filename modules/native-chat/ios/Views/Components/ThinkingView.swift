import SwiftUI

// MARK: - Thinking View

struct ThinkingView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.caption2)
                    .symbolEffect(.breathe)
                Text("Thinking")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.purple)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
        }
        .padding(10)
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.purple.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(8)
        .onAppear { animating = true }
    }
}
