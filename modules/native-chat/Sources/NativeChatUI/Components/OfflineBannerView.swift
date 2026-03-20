import SwiftUI

/// A banner displayed at the top of the chat view when the device is offline.
package struct OfflineBannerView: View {
    /// Whether the banner should be visible.
    let isVisible: Bool

    /// Scales icon-text spacing with Dynamic Type for accessibility.
    @ScaledMetric(relativeTo: .subheadline) private var iconSpacing: CGFloat = 8
    /// Scales horizontal padding with Dynamic Type for accessibility.
    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding: CGFloat = 16

    /// Creates an offline banner.
    /// - Parameter isVisible: Whether to show the banner.
    package init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    /// The banner body with icon, text, and slide animation.
    package var body: some View {
        if isVisible {
            HStack(spacing: iconSpacing) {
                Image(systemName: "wifi.slash")
                    .font(.subheadline)
                Text(String(localized: "You are offline"))
                    .font(.subheadline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.orange.gradient)
            .accessibilityLabel(String(localized: "Offline indicator"))
            .accessibilityIdentifier("banner.offline")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
