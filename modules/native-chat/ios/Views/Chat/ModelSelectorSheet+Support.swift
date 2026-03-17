import SwiftUI
import UIKit

struct ModelBadge: View {
    let model: ModelType
    let effort: ReasoningEffort
    let onTap: () -> Void

    var body: some View {
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
        .accessibilityIdentifier("chat.modelBadge")
    }

    private var badgeText: String {
        if effort == .none {
            return model.displayName
        }
        return "\(model.displayName) \(effort.displayName)"
    }
}

extension ModelSelectorSheet {
    struct Metrics {
        let contentHorizontalPadding: CGFloat
        let contentVerticalPadding: CGFloat
        let cardCornerRadius: CGFloat
        let panelCornerRadius: CGFloat
        let sheetMaxWidth: CGFloat?
        let rowVerticalPadding: CGFloat
        let rowHorizontalPadding: CGFloat
        let sectionSpacing: CGFloat
        let columnSpacing: CGFloat
        let reasoningColumnWidth: CGFloat?

        init(idiom: UIUserInterfaceIdiom) {
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

    func effortShortLabel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none: return "Off"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        case .xhigh: return "Max"
        }
    }
}
