import BackendContracts
import SwiftUI

struct SettingsStatusIndicator: View {
    let state: HealthCheckStateDTO?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay {
                Circle()
                    .strokeBorder(color.opacity(0.22), lineWidth: 4)
                    .padding(-4)
            }
            .accessibilityHidden(true)
    }

    private var color: Color {
        guard let state else {
            return Color.secondary
        }

        switch state {
        case .healthy:
            return Color.green
        case .degraded:
            return Color.orange
        case .unavailable, .invalid, .unauthorized:
            return Color.red
        case .missing:
            return Color.secondary
        }
    }
}
