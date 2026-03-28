import SwiftUI
import UIKit

/// Encapsulates UIKit keyboard dismissal so the backend-backed chat surfaces do not depend on the legacy ChatView.
@MainActor
enum KeyboardDismisser {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
