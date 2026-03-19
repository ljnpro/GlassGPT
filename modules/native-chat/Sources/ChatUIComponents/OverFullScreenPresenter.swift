import SwiftUI
import UIKit

/// UIViewControllerRepresentable that manages presenting SwiftUI content in an `.overFullScreen` modal.
public struct OverFullScreenPresenter<PresentedContent: View>: UIViewControllerRepresentable {
    /// Whether the modal is currently presented.
    @Binding public var isPresented: Bool
    /// Callback invoked when the modal is dismissed.
    public let onDismiss: () -> Void
    /// The user interface style override applied to the presented controller.
    public let interfaceStyle: UIUserInterfaceStyle
    /// Builder that produces the SwiftUI content to present.
    public let presentedContent: () -> PresentedContent

    /// Creates a presenter with the given presentation state and content builder.
    public init(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void,
        interfaceStyle: UIUserInterfaceStyle,
        presentedContent: @escaping () -> PresentedContent
    ) {
        self._isPresented = isPresented
        self.onDismiss = onDismiss
        self.interfaceStyle = interfaceStyle
        self.presentedContent = presentedContent
    }

    /// Creates the coordinator that tracks dismiss events.
    public func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onDismiss: onDismiss)
    }

    /// Creates the invisible anchor view controller that hosts modal presentations.
    public func makeUIViewController(context: Context) -> AnchorViewController<PresentedContent> {
        let controller = AnchorViewController<PresentedContent>()
        controller.onDismiss = {
            context.coordinator.handleDismiss()
        }
        return controller
    }

    /// Updates presentation state, presenting or dismissing the modal as needed.
    public func updateUIViewController(
        _ uiViewController: AnchorViewController<PresentedContent>,
        context: Context
    ) {
        uiViewController.onDismiss = {
            context.coordinator.handleDismiss()
        }
        uiViewController.updatePresentation(
            isPresented: isPresented,
            rootView: presentedContent(),
            interfaceStyle: interfaceStyle
        )
    }

    /// Coordinator that synchronizes dismiss callbacks with the SwiftUI binding.
    @MainActor
    public final class Coordinator {
        private var isPresented: Binding<Bool>
        private let onDismiss: () -> Void

        init(isPresented: Binding<Bool>, onDismiss: @escaping () -> Void) {
            self.isPresented = isPresented
            self.onDismiss = onDismiss
        }

        func handleDismiss() {
            guard isPresented.wrappedValue else { return }
            isPresented.wrappedValue = false
            onDismiss()
        }
    }
}

@MainActor
/// Zero-size anchor view controller that presents and manages an over-full-screen modal.
public final class AnchorViewController<PresentedContent: View>: UIViewController, UIAdaptivePresentationControllerDelegate {
    /// Closure invoked when the presented modal is dismissed.
    public var onDismiss: (() -> Void)?
    private var hostingController: DismissAwareHostingController<PresentedContent>?

    override public func loadView() {
        view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

    /// Presents or dismisses the hosted SwiftUI content based on the `isPresented` flag.
    public func updatePresentation(
        isPresented: Bool,
        rootView: PresentedContent,
        interfaceStyle: UIUserInterfaceStyle
    ) {
        if isPresented {
            if let hostingController {
                hostingController.rootView = rootView
                hostingController.overrideUserInterfaceStyle = interfaceStyle
                return
            }

            guard presentedViewController == nil else { return }
            let hostingController = DismissAwareHostingController(rootView: rootView)
            hostingController.dismissHandler = { [weak self] in
                self?.hostingController = nil
                self?.onDismiss?()
            }
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.view.backgroundColor = .clear
            hostingController.overrideUserInterfaceStyle = interfaceStyle
            present(hostingController, animated: true)
            self.hostingController = hostingController
            return
        }

        guard let hostingController, !hostingController.isBeingDismissed else { return }
        hostingController.dismiss(animated: true)
    }

    /// Handles interactive dismissal by cleaning up the hosting controller reference.
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        hostingController = nil
        onDismiss?()
    }
}

@MainActor
/// A `UIHostingController` subclass that fires a dismiss handler when it disappears.
public final class DismissAwareHostingController<Content: View>: UIHostingController<Content> {
    /// Closure called when this controller is dismissed from the screen.
    public var dismissHandler: (() -> Void)?

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        dismissHandler?()
        dismissHandler = nil
    }
}
