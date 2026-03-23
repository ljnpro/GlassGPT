import ChatUIComponents
import SwiftUI

struct SettingsActionButtonStyle: ButtonStyle {
    enum Kind {
        case standard
        case prominent
        case destructive
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        baseLabel(for: configuration)
    }

    @ViewBuilder
    private func baseLabel(for configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .opacity(opacity(for: configuration.isPressed))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.82), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isEnabled)

        switch kind {
        case .standard:
            label
                .background(backgroundFill, in: Capsule())
                .singleFrameGlassCapsuleControl(
                    tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                    borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                    darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                    lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                )
        case .prominent, .destructive:
            label
                .background(backgroundFill, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(isEnabled ? 0.18 : 0.12), lineWidth: 1)
                }
        }
    }

    private var foregroundStyle: Color {
        guard isEnabled else {
            return Color.primary.opacity(0.78)
        }

        return switch kind {
        case .standard:
            Color.primary
        case .prominent:
            Color.white
        case .destructive:
            Color.white
        }
    }

    private func opacity(for isPressed: Bool) -> Double {
        if isEnabled {
            return isPressed ? 0.82 : 1
        }
        return 1
    }

    private var backgroundFill: Color {
        guard isEnabled else {
            return Color.primary.opacity(0.14)
        }

        switch kind {
        case .standard:
            return Color.primary.opacity(0.06)
        case .prominent:
            return .accentColor
        case .destructive:
            return Color(red: 0.82, green: 0.12, blue: 0.18)
        }
    }
}
