import SwiftUI
import UIKit

public struct HapticService: Sendable {
    public init() {}

    public func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, isEnabled: Bool) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    public func notify(_ type: UINotificationFeedbackGenerator.FeedbackType, isEnabled: Bool) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    public func selection(isEnabled: Bool) {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

private struct HapticsEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var hapticsEnabled: Bool {
        get { self[HapticsEnabledKey.self] }
        set { self[HapticsEnabledKey.self] = newValue }
    }
}
