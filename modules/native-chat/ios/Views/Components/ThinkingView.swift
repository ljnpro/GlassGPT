import SwiftUI

// MARK: - Thinking Indicator (shown while model is actively reasoning)

struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.caption)
                .symbolEffect(.breathe)
                .foregroundStyle(.purple)

            Text("Thinking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)

            // Animated dots
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.purple.opacity(0.6))
                        .frame(width: 5, height: 5)
                        .scaleEffect(animating ? 1.0 : 0.4)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: animating
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.purple.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.purple.opacity(0.15), lineWidth: 1)
        )
        .onAppear { animating = true }
    }
}

// MARK: - Thinking View (shows accumulated thinking text)

struct ThinkingView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.caption2)
                Text("Reasoning")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.purple)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .textSelection(.enabled)
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
