import SwiftUI

/// Animated indicator shown when the model is searching uploaded documents via file_search.
/// Includes a built-in timeout: if the indicator stays visible for more than 60 seconds,
/// it automatically fades out to prevent a stuck UI state.
struct FileSearchIndicator: View {
    @State private var timedOut = false

    /// Timeout duration in seconds before auto-dismissing
    private let timeoutSeconds: Double = 60

    var body: some View {
        if !timedOut {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.teal)
                    .symbolEffect(.pulse, options: .repeating)

                Text("Reading documents…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .singleSurfaceGlass(
                cornerRadius: 999,
                stableFillOpacity: 0.01,
                borderWidth: 0.75,
                darkBorderOpacity: 0.14,
                lightBorderOpacity: 0.08
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .onAppear {
                // Start timeout timer
                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        timedOut = true
                    }
                }
            }
        }
    }
}
