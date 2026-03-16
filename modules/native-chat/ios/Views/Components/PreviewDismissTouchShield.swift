import UIKit

@MainActor
enum PreviewDismissTouchShield {
    private static var shieldWindow: UIWindow?

    static func activate() {
        guard shieldWindow == nil else {
            shieldWindow?.isHidden = false
            return
        }

        guard let windowScene = preferredWindowScene() else { return }

        let shieldWindow = TouchShieldWindow(windowScene: windowScene)
        shieldWindow.windowLevel = .alert + 1
        shieldWindow.backgroundColor = .clear
        shieldWindow.isOpaque = false
        shieldWindow.rootViewController = TouchShieldViewController()
        shieldWindow.isHidden = false
        self.shieldWindow = shieldWindow
    }

    static func deactivate() {
        shieldWindow?.isHidden = true
        shieldWindow?.rootViewController = nil
        shieldWindow = nil
    }

    private static func preferredWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}

private final class TouchShieldWindow: UIWindow {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden && alpha > 0.001 && isUserInteractionEnabled
    }
}

private final class TouchShieldViewController: UIViewController {
    override func loadView() {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = true
        view.accessibilityViewIsModal = true
        self.view = view
    }
}
