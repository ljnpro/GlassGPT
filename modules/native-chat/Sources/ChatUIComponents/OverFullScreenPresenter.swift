import SwiftUI
import UIKit

public struct OverFullScreenPresenter<PresentedContent: View>: UIViewControllerRepresentable {
    @Binding public var isPresented: Bool
    public let onDismiss: () -> Void
    public let interfaceStyle: UIUserInterfaceStyle
    public let presentedContent: () -> PresentedContent

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

    public func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onDismiss: onDismiss)
    }

    public func makeUIViewController(context: Context) -> AnchorViewController<PresentedContent> {
        let controller = AnchorViewController<PresentedContent>()
        controller.onDismiss = {
            context.coordinator.handleDismiss()
        }
        return controller
    }

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
public final class AnchorViewController<PresentedContent: View>: UIViewController, UIAdaptivePresentationControllerDelegate {
    public var onDismiss: (() -> Void)?
    private var hostingController: DismissAwareHostingController<PresentedContent>?

    override public func loadView() {
        view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

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

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        hostingController = nil
        onDismiss?()
    }
}

@MainActor
public final class DismissAwareHostingController<Content: View>: UIHostingController<Content> {
    public var dismissHandler: (() -> Void)?

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        dismissHandler?()
        dismissHandler = nil
    }
}
