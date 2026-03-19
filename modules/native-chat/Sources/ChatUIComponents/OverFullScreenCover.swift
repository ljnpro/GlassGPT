import SwiftUI
import UIKit

public extension View {
    /// Presents content in an `.overFullScreen` modal with a cross-dissolve transition.
    func overFullScreenCover(
        isPresented: Binding<Bool>,
        interfaceStyle: UIUserInterfaceStyle = .unspecified,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        background(
            OverFullScreenPresenter(
                isPresented: isPresented,
                onDismiss: onDismiss,
                interfaceStyle: interfaceStyle,
                presentedContent: content
            )
        )
    }
}
