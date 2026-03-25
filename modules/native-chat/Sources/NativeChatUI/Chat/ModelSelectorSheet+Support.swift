import ChatDomain
import ChatUIComponents
import SwiftUI
import UIKit

/// Header row showing the reasoning control title and the currently selected effort.
package struct ModelSelectorReasoningHeader: View {
    /// The currently selected reasoning effort shown in the header.
    let reasoningEffort: ReasoningEffort

    /// The header content used above the reasoning slider.
    package var body: some View {
        HStack {
            Text(String(localized: "Reasoning"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(reasoningEffort.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: reasoningEffort)
                .accessibilityLabel(String(localized: "Current reasoning effort") + ": \(reasoningEffort.displayName)")
                .accessibilityIdentifier("modelSelector.reasoningValue")
        }
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
