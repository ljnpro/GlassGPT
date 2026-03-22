import UIKit

/// Shared visual constants for Liquid Glass surfaces and controls.
package enum GlassStyleMetrics {
    /// Metrics used by compact capsule-style controls.
    package enum CapsuleControl {
        package static let tintOpacity: CGFloat = 0.015
        package static let borderWidth: CGFloat = 0.78
        package static let darkBorderOpacity: CGFloat = 0.14
        package static let lightBorderOpacity: CGFloat = 0.08
    }

    /// Metrics used by compact inset glass cards.
    package enum CompactSurface {
        package static let stableFillOpacity: CGFloat = 0.012
        package static let tintOpacity: CGFloat = 0.022
        package static let borderWidth: CGFloat = 0.8
        package static let darkBorderOpacity: CGFloat = 0.15
        package static let lightBorderOpacity: CGFloat = 0.085
    }

    /// Metrics used by elevated panels with a stronger shadow treatment.
    package enum ElevatedPanel {
        package static let stableFillOpacity: CGFloat = 0.014
        package static let tintOpacity: CGFloat = 0.026
        package static let borderWidth: CGFloat = 0.9
        package static let darkBorderOpacity: CGFloat = 0.17
        package static let lightBorderOpacity: CGFloat = 0.095
        package static let shadowOpacity: CGFloat = 0.08
        package static let shadowRadius: CGFloat = 24
        package static let shadowYOffset: CGFloat = 10
    }

    /// Metrics used by live streaming surfaces.
    package enum LiveSurface {
        package static let tintOpacity: CGFloat = 0.03
        package static let activeTintOpacity: CGFloat = 0.024
    }

    /// Metrics used by assistant message surfaces.
    package enum AssistantSurface {
        package static let liveStableFillOpacity: CGFloat = 0.01
        package static let idleStableFillOpacity: CGFloat = 0.004
        package static let liveTintOpacity: CGFloat = 0.03
        package static let idleTintOpacity: CGFloat = 0.024
        package static let borderWidth: CGFloat = 0.85
        package static let darkBorderOpacity: CGFloat = 0.16
        package static let lightBorderOpacity: CGFloat = 0.09
    }

    /// Metrics used by the lightest background treatments.
    package enum SubtleSurface {
        package static let stableFillOpacity: CGFloat = 0.01
        package static let borderWidth: CGFloat = 0.75
        package static let darkBorderOpacity: CGFloat = 0.14
        package static let lightBorderOpacity: CGFloat = 0.08
    }
}
