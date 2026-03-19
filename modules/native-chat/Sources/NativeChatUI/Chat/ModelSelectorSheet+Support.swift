import ChatDomain
import ChatUIComponents
import SwiftUI
import UIKit

/// Compact capsule badge displaying the current model name and reasoning effort, tappable to open the model selector.
package struct ModelBadge: View {
    /// The currently selected model.
    let model: ModelType
    /// The currently selected reasoning effort level.
    let effort: ReasoningEffort
    /// Callback invoked when the badge is tapped.
    let onTap: () -> Void

    /// Creates a model badge for the given model and effort.
    package init(model: ModelType, effort: ReasoningEffort, onTap: @escaping () -> Void) {
        self.model = model
        self.effort = effort
        self.onTap = onTap
    }

    /// The badge surface showing the current model and reasoning effort.
    package var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(badgeText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .fixedSize(horizontal: true, vertical: false)
            .singleFrameGlassCapsuleControl(
                tintOpacity: 0.015,
                borderWidth: 0.78,
                darkBorderOpacity: 0.14,
                lightBorderOpacity: 0.08
            )
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(String(localized: "Model") + ": \(badgeText). " + String(localized: "Tap to change"))
        .accessibilityIdentifier("chat.modelBadge")
    }

    private var badgeText: String {
        if effort == .none {
            return model.displayName
        }
        return "\(model.displayName) \(effort.displayName)"
    }
}

public extension ModelSelectorSheet {
    /// Layout metrics for the model selector sheet, adapted for phone and iPad idioms.
    struct Metrics {
        /// Horizontal padding applied to the sheet content.
        public let contentHorizontalPadding: CGFloat
        /// Vertical padding applied to the sheet content.
        public let contentVerticalPadding: CGFloat
        /// Corner radius of inner cards (toggle group, reasoning control).
        public let cardCornerRadius: CGFloat
        /// Corner radius of the outer panel.
        public let panelCornerRadius: CGFloat
        /// Maximum width of the sheet, nil for phone.
        public let sheetMaxWidth: CGFloat?
        /// Vertical padding inside each toggle row.
        public let rowVerticalPadding: CGFloat
        /// Horizontal padding inside each toggle row.
        public let rowHorizontalPadding: CGFloat
        /// Spacing between major sections of the sheet.
        public let sectionSpacing: CGFloat
        /// Spacing between columns in two-column layout.
        public let columnSpacing: CGFloat
        /// Fixed width for the reasoning control column on iPad.
        public let reasoningColumnWidth: CGFloat?

        /// Creates metrics appropriate for the given user interface idiom.
        public init(idiom: UIUserInterfaceIdiom) {
            switch idiom {
            case .pad:
                contentHorizontalPadding = 24
                contentVerticalPadding = 22
                cardCornerRadius = 28
                panelCornerRadius = 36
                sheetMaxWidth = 620
                rowVerticalPadding = 18
                rowHorizontalPadding = 22
                sectionSpacing = 18
                columnSpacing = 18
                reasoningColumnWidth = 280
            default:
                contentHorizontalPadding = 20
                contentVerticalPadding = 18
                cardCornerRadius = 24
                panelCornerRadius = 32
                sheetMaxWidth = nil
                rowVerticalPadding = 16
                rowHorizontalPadding = 18
                sectionSpacing = 16
                columnSpacing = 14
                reasoningColumnWidth = nil
            }
        }
    }

    /// Returns an abbreviated label for the given reasoning effort level.
    func effortShortLabel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none: String(localized: "Off")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Med")
        case .high: String(localized: "High")
        case .xhigh: String(localized: "Max")
        }
    }
}
