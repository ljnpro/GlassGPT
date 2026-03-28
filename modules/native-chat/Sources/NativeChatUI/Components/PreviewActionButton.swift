import ChatUIComponents
import SwiftUI

struct PreviewActionButton<Label: View>: View {
    let diameter: CGFloat
    let isEnabled: Bool
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    var onTriggerStart: () -> Void = {}
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false

    private var hitBounds: CGRect {
        CGRect(x: 0, y: 0, width: diameter, height: diameter)
    }

    var body: some View {
        label()
            .frame(width: diameter, height: diameter)
            .singleFrameGlassCircleControl(
                tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
            )
            .scaleEffect(isPressed ? 0.9 : 1)
            .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.62)
            .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isPressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        isPressed = hitBounds.contains(value.location)
                    }
                    .onEnded { value in
                        let shouldTrigger = isEnabled && hitBounds.contains(value.location)
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
                            isPressed = false
                        }

                        guard shouldTrigger else { return }
                        onTriggerStart()
                        Task { @MainActor in
                            do {
                                try await Task.sleep(nanoseconds: 55_000_000)
                            } catch {
                                return
                            }
                            action()
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
            .accessibilityAction {
                guard isEnabled else { return }
                action()
            }
    }
}
