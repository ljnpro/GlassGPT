import SwiftUI
import UIKit
import ChatUIComponents

extension View {
    func overFullScreenCover<PresentedContent: View>(
        isPresented: Binding<Bool>,
        interfaceStyle: UIUserInterfaceStyle = .unspecified,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> PresentedContent
    ) -> some View {
        background(
            ChatUIComponents.OverFullScreenPresenter(
                isPresented: isPresented,
                onDismiss: onDismiss,
                interfaceStyle: interfaceStyle,
                presentedContent: content
            )
        )
    }
}
