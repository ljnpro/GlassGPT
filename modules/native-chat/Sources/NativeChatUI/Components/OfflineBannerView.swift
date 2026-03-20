import SwiftUI

/// A banner displayed at the top of the chat view when the device is offline.
package struct OfflineBannerView: View {
    /// Whether the banner should be visible.
    let isVisible: Bool

    /// Creates an offline banner.
    /// - Parameter isVisible: Whether to show the banner.
    package init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    /// The banner body with icon, text, and slide animation.
    package var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.subheadline)
                Text(String(localized: "You are offline"))
                    .font(.subheadline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.orange.gradient)
            .accessibilityLabel(String(localized: "Offline indicator"))
            .accessibilityIdentifier("banner.offline")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
