import ChatUIComponents
import SwiftUI

/// Shared full-width selector capsule used by Chat and Agent top bars.
public struct ConversationSelectorCapsuleButton: View {
    let title: String
    let leadingSystemIcon: String?
    let trailingSystemIcons: [String]
    let accessibilityLabel: String
    let accessibilityValue: String?
    let accessibilityHint: String?
    let accessibilityIdentifier: String
    let onTap: () -> Void

    /// Creates a shared top-bar selector capsule.
    public init(
        title: String,
        leadingSystemIcon: String? = nil,
        trailingSystemIcons: [String] = [],
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        accessibilityHint: String? = nil,
        accessibilityIdentifier: String,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.leadingSystemIcon = leadingSystemIcon
        self.trailingSystemIcons = trailingSystemIcons
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityHint = accessibilityHint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
    }

    /// The rendered full-width selector capsule.
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if let leadingSystemIcon {
                    Image(systemName: leadingSystemIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(trailingSystemIcons.enumerated()), id: \.offset) { _, systemName in
                    Image(systemName: systemName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .singleFrameGlassCapsuleControl(
                tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? title)
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Shared new-conversation button used by Chat and Agent top bars.
public struct ConversationNewButton: View {
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let onTap: () -> Void

    /// Creates a shared new-conversation button.
    public init(
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        onTap: @escaping () -> Void
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
    }

    /// The rendered new-conversation capsule button.
    public var body: some View {
        Button(action: onTap) {
            Image(systemName: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .singleFrameGlassCapsuleControl(
                    tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                    borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                    darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                    lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                )
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
