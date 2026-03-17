import SwiftUI
import UIKit
import ChatUI

extension View {
    func overFullScreenCover<PresentedContent: View>(
        isPresented: Binding<Bool>,
        interfaceStyle: UIUserInterfaceStyle = .unspecified,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> PresentedContent
    ) -> some View {
        background(
            ChatUI.OverFullScreenPresenter(
                isPresented: isPresented,
                onDismiss: onDismiss,
                interfaceStyle: interfaceStyle,
                presentedContent: content
            )
        )
    }
}
