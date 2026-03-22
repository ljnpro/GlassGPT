import SwiftUI
import UIKit

/// Thin wrapper around UIKit haptic feedback generators with a global enable/disable toggle.
public struct HapticService: Sendable {
    public static let shared = HapticService()

    /// Creates a new haptic service instance.
    public init() {}

    /// Triggers an impact haptic of the given style when haptics are enabled.
    public func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, isEnabled: Bool) {
        guard isEnabled else { return }
        runOnMainActor {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    /// Triggers a notification haptic (success, warning, or error) when haptics are enabled.
    public func notify(_ type: UINotificationFeedbackGenerator.FeedbackType, isEnabled: Bool) {
        guard isEnabled else { return }
        runOnMainActor {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }
    }

    /// Triggers a selection-change haptic tap when haptics are enabled.
    public func selection(isEnabled: Bool) {
        guard isEnabled else { return }
        runOnMainActor {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        }
    }

    private func runOnMainActor(_ operation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            operation()
        }
    }
}

public extension EnvironmentValues {
    /// Whether haptic feedback is enabled for the current view hierarchy.
    @Entry var hapticsEnabled = false
}
