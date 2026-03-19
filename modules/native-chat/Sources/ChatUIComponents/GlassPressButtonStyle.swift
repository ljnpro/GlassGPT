import SwiftUI

/// A button style that subtly scales down and dims the label while pressed, providing tactile feedback.
public struct GlassPressButtonStyle: ButtonStyle {
    /// Scale factor applied to the label when the button is pressed.
    public var pressedScale: CGFloat
    /// Opacity applied to the label when the button is pressed.
    public var pressedOpacity: Double

    /// Creates a press-style button with configurable scale and opacity values.
    public init(pressedScale: CGFloat = 0.965, pressedOpacity: Double = 0.92) {
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
    }

    /// Applies a spring-animated scale and opacity effect when the button is pressed.
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
