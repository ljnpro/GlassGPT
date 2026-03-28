import CoreGraphics
import UIKit

/// Device-adaptive spacing and sizing metrics for chat and agent selector sheets.
package struct SelectorSheetMetrics {
    package let contentHorizontalPadding: CGFloat
    package let contentVerticalPadding: CGFloat
    package let cardCornerRadius: CGFloat
    package let panelCornerRadius: CGFloat
    package let sheetMaxWidth: CGFloat?
    package let rowVerticalPadding: CGFloat
    package let rowHorizontalPadding: CGFloat
    package let sectionSpacing: CGFloat
    package let columnSpacing: CGFloat
    package let reasoningColumnWidth: CGFloat?

    /// Creates selector sheet metrics tuned for the current device idiom.
    package init(idiom: UIUserInterfaceIdiom) {
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
