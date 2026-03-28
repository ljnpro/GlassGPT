import ChatUIComponents
import SwiftUI

struct BackendConversationErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .singleSurfaceGlass(
            cornerRadius: 12,
            stableFillOpacity: 0.01,
            borderWidth: 0.75,
            darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
        )
    }
}
