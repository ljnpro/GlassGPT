import SwiftUI

/// Animated indicator shown in the streaming bubble when the model is performing a web search.
struct WebSearchIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, options: .repeating)

            Text("Searching the web…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: Capsule())
    }
}
