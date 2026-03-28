import SwiftUI

/// Accent CTA button used in Settings empty and recovery-oriented account flows.
public struct SettingsCallToActionButton: View {
    private let title: String
    private let accessibilityIdentifier: String
    private let action: () -> Void

    /// Creates a settings CTA button with a title, accessibility identifier, and tap action.
    public init(
        title: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.04, green: 0.26, blue: 0.68))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
