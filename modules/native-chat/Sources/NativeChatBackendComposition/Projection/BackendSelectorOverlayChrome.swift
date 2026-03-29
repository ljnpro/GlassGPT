import ChatDomain
import SwiftUI
import UIKit

struct BackendSelectorOverlayChrome<Sheet: View>: View {
    let selectedTheme: AppTheme
    let maxPhonePanelWidth: CGFloat
    let onDismiss: () -> Void
    @ViewBuilder let sheet: () -> Sheet

    var body: some View {
        GeometryReader { geometry in
            let idiom = UIDevice.current.userInterfaceIdiom
            let horizontalInset = idiom == .pad ? 32.0 : 16.0
            let maxPanelWidth = idiom == .pad ? 680.0 : min(geometry.size.width - (horizontalInset * 2), maxPhonePanelWidth)
            let topInset = idiom == .pad ? 76.0 : 60.0

            ZStack(alignment: .top) {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                sheet()
                    .frame(maxWidth: maxPanelWidth)
                    .padding(.top, topInset)
                    .padding(.horizontal, horizontalInset)
            }
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}
