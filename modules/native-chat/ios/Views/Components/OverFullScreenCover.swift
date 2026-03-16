import SwiftUI
import UIKit

struct OverFullScreenPresenter<PresentedContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    let interfaceStyle: UIUserInterfaceStyle
    let presentedContent: () -> PresentedContent

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> AnchorViewController<PresentedContent> {
        let controller = AnchorViewController<PresentedContent>()
        controller.onDismiss = {
            context.coordinator.handleDismiss()
        }
        return controller
    }

    func updateUIViewController(
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
    final class Coordinator {
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
final class AnchorViewController<PresentedContent: View>: UIViewController, UIAdaptivePresentationControllerDelegate {
    var onDismiss: (() -> Void)?
    private var hostingController: DismissAwareHostingController<PresentedContent>?

    override func loadView() {
        view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
    }

    func updatePresentation(
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

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        hostingController = nil
        onDismiss?()
    }
}

@MainActor
final class DismissAwareHostingController<Content: View>: UIHostingController<Content> {
    var dismissHandler: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        dismissHandler?()
        dismissHandler = nil
    }
}

extension View {
    func overFullScreenCover<PresentedContent: View>(
        isPresented: Binding<Bool>,
        interfaceStyle: UIUserInterfaceStyle = .unspecified,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> PresentedContent
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
