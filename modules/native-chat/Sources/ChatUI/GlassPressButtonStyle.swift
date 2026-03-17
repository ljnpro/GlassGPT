import SwiftUI

public struct GlassPressButtonStyle: ButtonStyle {
    public var pressedScale: CGFloat
    public var pressedOpacity: Double

    public init(pressedScale: CGFloat = 0.965, pressedOpacity: Double = 0.92) {
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
